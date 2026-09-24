//! Best-effort ownership in the current proc mount; no cmdline or environ reads.
use serde::Serialize;
use std::{
    collections::{HashMap, HashSet},
    fs::{self, File},
    io::{self, Read},
    path::Path,
    time::Instant,
};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Owner {
    pub pid: u32,
    pub start_time_ticks: String,
    pub name: String,
}
impl Owner {
    fn observed(pid: u32, before: u64, after: u64, name: String) -> Option<Self> {
        (before == after).then(|| Self {
            pid,
            start_time_ticks: before.to_string(),
            name,
        })
    }
}
#[derive(Default, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Coverage {
    pub denied: usize,
    pub races: usize,
    pub errors: usize,
    pub timed_out: bool,
    pub scan_limited: bool,
    pub owners_omitted: usize,
}
impl Coverage {
    fn error(&mut self, error: io::Error) {
        match error.kind() {
            io::ErrorKind::PermissionDenied => self.denied += 1,
            io::ErrorKind::NotFound => self.races += 1,
            _ => self.errors += 1,
        }
    }
    pub fn partial(&self) -> bool {
        self.denied + self.races + self.errors + self.owners_omitted > 0
            || self.timed_out
            || self.scan_limited
    }
}
fn read_small(path: &Path) -> io::Result<String> {
    let mut bytes = Vec::new();
    File::open(path)?.take(4097).read_to_end(&mut bytes)?;
    if bytes.len() > 4096 {
        return Err(io::ErrorKind::InvalidData.into());
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}
pub fn start_time(stat: &str) -> Option<u64> {
    // comm may contain spaces and ')'; field 22 is token 19 after the final ')'.
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}
fn identity(path: &Path) -> io::Result<u64> {
    start_time(&read_small(&path.join("stat"))?).ok_or(io::ErrorKind::InvalidData.into())
}
fn socket_inode(path: &Path) -> io::Result<Option<u32>> {
    let link = fs::read_link(path)?;
    Ok(link
        .to_str()
        .and_then(|s| s.strip_prefix("socket:["))
        .and_then(|s| s.strip_suffix(']'))
        .and_then(|s| s.parse().ok()))
}

pub fn scan(
    root: &Path,
    wanted: &HashSet<u32>,
    deadline: Instant,
) -> (HashMap<u32, Vec<Owner>>, Coverage) {
    let mut result: HashMap<u32, Vec<Owner>> = HashMap::new();
    let mut coverage = Coverage::default();
    if wanted.is_empty() {
        return (result, coverage);
    }
    let entries = match fs::read_dir(root) {
        Ok(v) => v,
        Err(e) => {
            coverage.error(e);
            return (result, coverage);
        }
    };
    let mut fd_count = 0;
    for (entry_count, entry) in entries.enumerate() {
        if Instant::now() >= deadline {
            coverage.timed_out = true;
            break;
        }
        if entry_count >= 65536 {
            coverage.scan_limited = true;
            break;
        }
        let entry = match entry {
            Ok(v) => v,
            Err(e) => {
                coverage.error(e);
                continue;
            }
        };
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<u32>().ok())
        else {
            continue;
        };
        let path = entry.path();
        let before = match identity(&path) {
            Ok(v) => v,
            Err(e) => {
                coverage.error(e);
                continue;
            }
        };
        let fds = match fs::read_dir(path.join("fd")) {
            Ok(v) => v,
            Err(e) => {
                coverage.error(e);
                continue;
            }
        };
        let mut matches = HashSet::new();
        for fd in fds {
            if Instant::now() >= deadline {
                coverage.timed_out = true;
                break;
            }
            fd_count += 1;
            if fd_count > 262144 {
                coverage.scan_limited = true;
                break;
            }
            let fd = match fd {
                Ok(v) => v,
                Err(e) => {
                    coverage.error(e);
                    continue;
                }
            };
            match socket_inode(&fd.path()) {
                Ok(Some(inode)) if wanted.contains(&inode) => {
                    matches.insert(inode);
                }
                Ok(_) => {}
                Err(e) => coverage.error(e),
            }
        }
        if coverage.timed_out || coverage.scan_limited {
            break;
        }
        if matches.is_empty() {
            continue;
        }
        let name = match read_small(&path.join("comm")) {
            Ok(v) => v
                .trim_end_matches('\n')
                .chars()
                .filter(|c| !c.is_control())
                .take(128)
                .collect::<String>(),
            Err(e) => {
                coverage.error(e);
                continue;
            }
        };
        let after = match identity(&path) {
            Ok(v) => v,
            Err(e) => {
                coverage.error(e);
                continue;
            }
        };
        let Some(owner) = Owner::observed(pid, before, after, name) else {
            coverage.races += 1;
            continue;
        };
        for inode in matches {
            let owners = result.entry(inode).or_default();
            if owners.len() < 16 {
                owners.push(owner.clone());
            } else {
                coverage.owners_omitted += 1;
            }
        }
    }
    for owners in result.values_mut() {
        owners.sort_by_key(|o| o.pid);
    }
    (result, coverage)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stat_names_do_not_shift_identity() {
        let stat = format!(
            "12 (a name ) with brackets) S {} 987 0",
            vec!["0"; 18].join(" ")
        );
        assert_eq!(start_time(&stat), Some(987));
        assert_eq!(start_time("invalid"), None);
    }
    #[test]
    fn failures_and_pid_reuse_are_distinct() {
        let mut coverage = Coverage::default();
        coverage.error(io::ErrorKind::PermissionDenied.into());
        coverage.error(io::ErrorKind::NotFound.into());
        coverage.error(io::ErrorKind::InvalidData.into());
        assert_eq!(
            (coverage.denied, coverage.races, coverage.errors),
            (1, 1, 1)
        );
        assert!(Owner::observed(4, 1, 2, "reused".into()).is_none());
        assert!(Owner::observed(4, 1, 1, "stable".into()).is_some());
        assert_ne!(
            Owner {
                pid: 4,
                start_time_ticks: "1".into(),
                name: "a".into()
            },
            Owner {
                pid: 4,
                start_time_ticks: "2".into(),
                name: "a".into()
            }
        );
    }
}
