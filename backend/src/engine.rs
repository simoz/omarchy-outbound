use crate::{
    geo::{Geo, Status},
    netlink::{self, Endpoint, Failure, Socket},
    owners::{self, Coverage, Owner},
    scope::{self, Scope},
};
use serde::Serialize;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs::File,
    io::{self, Read},
    path::Path,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub const MAX_SOCKETS: usize = 4096;
pub const MAX_LINE: usize = 2 * 1024 * 1024;
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Connection {
    pub id: String,
    pub family: &'static str,
    pub local: Endpoint,
    pub remote: Endpoint,
    pub state: &'static str,
    pub uid: u32,
    pub owners: Vec<Owner>,
    pub scope: Scope,
    pub direction: &'static str,
    pub country: Option<String>,
}
#[derive(Default, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Aggregates {
    pub sockets: usize,
    pub countries: BTreeMap<String, usize>,
    pub applications: BTreeMap<String, usize>,
    pub unknown_owners: usize,
}
impl Aggregates {
    fn from_rows(rows: &[Connection]) -> Self {
        let mut a = Self {
            sockets: rows.len(),
            ..Self::default()
        };
        for row in rows {
            let country = row
                .country
                .as_deref()
                .unwrap_or(if row.scope == Scope::Public {
                    "unknown"
                } else {
                    "nonInternet"
                });
            *a.countries.entry(country.into()).or_default() += 1;
            if row.owners.is_empty() {
                a.unknown_owners += 1;
            }
            let names: HashSet<&str> = row.owners.iter().map(|o| o.name.as_str()).collect();
            for name in names {
                *a.applications.entry(name.into()).or_default() += 1;
            }
        }
        a
    }
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub version: u8,
    pub kind: &'static str,
    pub request_id: String,
    pub session: String,
    pub sequence: u64,
    pub observed_at_ms: u64,
    pub status: &'static str,
    pub coverage: SnapshotCoverage,
    pub database: Status,
    pub connections: Vec<Connection>,
    pub aggregates: Aggregates,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotCoverage {
    /// null means a complete family dump; other values identify failure categories.
    pub ipv4: Option<Failure>,
    pub ipv6: Option<Failure>,
    pub processes: Coverage,
    pub omitted_rows: usize,
    pub truncated: bool,
    pub namespace: &'static str,
}
pub struct Engine {
    session: String,
    sequence: u64,
    geo: Geo,
    fallback: HashMap<String, String>,
    next_id: u64,
}
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
impl Engine {
    pub fn new(database: Option<&Path>) -> io::Result<Self> {
        let mut random = [0u8; 16];
        File::open("/dev/urandom")?.read_exact(&mut random)?;
        Ok(Self {
            session: random.iter().map(|b| format!("{b:02x}")).collect(),
            sequence: 0,
            geo: Geo::load(database, now_ms() / 1000),
            fallback: HashMap::new(),
            next_id: 0,
        })
    }
    pub fn sample(&mut self, request_id: String) -> Snapshot {
        self.sequence += 1;
        let mut rows = Vec::new();
        let mut omitted = 0;
        let mut failures = [None; 2];
        for (i, family) in [2, 10].into_iter().enumerate() {
            match netlink::collect(
                family,
                i as u32 + 1,
                MAX_SOCKETS - rows.len(),
                Instant::now() + Duration::from_secs(1),
            ) {
                Ok(dump) => {
                    omitted += dump.omitted;
                    rows.extend(dump.sockets);
                }
                Err(error) => failures[i] = Some(error),
            }
        }
        let wanted = rows.iter().map(|s| s.inode).filter(|i| *i != 0).collect();
        let (owners, process_coverage) = owners::scan(
            Path::new("/proc"),
            &wanted,
            Instant::now() + Duration::from_millis(400),
        );
        self.snapshot(
            request_id,
            rows,
            owners,
            SnapshotCoverage {
                ipv4: failures[0],
                ipv6: failures[1],
                processes: process_coverage,
                omitted_rows: omitted,
                truncated: omitted > 0,
                namespace: "current",
            },
        )
    }
    fn snapshot(
        &mut self,
        request_id: String,
        rows: Vec<Socket>,
        owners: HashMap<u32, Vec<Owner>>,
        coverage: SnapshotCoverage,
    ) -> Snapshot {
        let mut next_fallback = HashMap::new();
        let connections: Vec<_> = rows
            .into_iter()
            .map(|row| {
                let id = if row.cookie != [u32::MAX; 2] {
                    format!(
                        "{}:{}:{:08x}{:08x}",
                        self.session, row.family, row.cookie[0], row.cookie[1]
                    )
                } else {
                    let key = format!(
                        "{}:{}:{:?}:{:?}",
                        row.family, row.inode, row.local, row.remote
                    );
                    let id = self.fallback.get(&key).cloned().unwrap_or_else(|| {
                        self.next_id += 1;
                        format!("{}:fallback:{}", self.session, self.next_id)
                    });
                    next_fallback.insert(key, id.clone());
                    id
                };
                let country = self.geo.lookup(row.remote.address);
                Connection {
                    id,
                    family: if row.family == 2 { "IPv4" } else { "IPv6" },
                    scope: scope::classify(row.remote.address),
                    country,
                    owners: owners.get(&row.inode).cloned().unwrap_or_default(),
                    local: row.local,
                    remote: row.remote,
                    state: netlink::state_name(row.state),
                    uid: row.uid,
                    direction: "unknown",
                }
            })
            .collect();
        self.fallback = next_fallback;
        let status = if coverage.ipv4.is_some() && coverage.ipv6.is_some() {
            "error"
        } else if coverage.ipv4.is_some()
            || coverage.ipv6.is_some()
            || coverage.processes.partial()
            || coverage.truncated
            || connections.iter().any(|c| c.owners.is_empty())
        {
            "partial"
        } else {
            "ok"
        };
        let observed_at_ms = now_ms();
        let mut database = self.geo.status.clone();
        database.stale = database.build_epoch_seconds.is_some_and(|epoch| {
            observed_at_ms.saturating_div(1000).saturating_sub(epoch) > 90 * 86400
        });
        Snapshot {
            version: 1,
            kind: "snapshot",
            request_id,
            session: self.session.clone(),
            sequence: self.sequence,
            observed_at_ms,
            status,
            database,
            coverage,
            aggregates: Aggregates::from_rows(&connections),
            connections,
        }
    }
}
impl Snapshot {
    pub fn encode_bounded(&mut self) -> serde_json::Result<Vec<u8>> {
        loop {
            let mut bytes = serde_json::to_vec(self)?;
            if bytes.len() < MAX_LINE {
                bytes.push(b'\n');
                return Ok(bytes);
            }
            // Bound wire size even when escaped Unicode names and shared owners
            // make 4,096 rows exceed the byte limit. Recount only emitted rows.
            let keep = self.connections.len() / 2;
            self.coverage.omitted_rows += self.connections.len() - keep;
            self.coverage.truncated = true;
            self.status = "partial";
            self.connections.truncate(keep);
            self.aggregates = Aggregates::from_rows(&self.connections);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn socket() -> Socket {
        Socket {
            family: 2,
            local: Endpoint {
                address: "127.0.0.1".parse().unwrap(),
                port: 10,
            },
            remote: Endpoint {
                address: "192.0.2.1".parse().unwrap(),
                port: 20,
            },
            state: 1,
            inode: 1,
            uid: 1000,
            cookie: [u32::MAX; 2],
        }
    }
    fn coverage() -> SnapshotCoverage {
        SnapshotCoverage {
            ipv4: None,
            ipv6: None,
            processes: Coverage::default(),
            omitted_rows: 0,
            truncated: false,
            namespace: "current",
        }
    }
    #[test]
    fn fallback_ids_retire_and_shared_owners_do_not_double_count() {
        let mut engine = Engine::new(None).unwrap();
        let owner = |pid, name: &str| Owner {
            pid,
            start_time_ticks: "8".into(),
            name: name.into(),
        };
        let owners = HashMap::from([(
            1,
            vec![owner(2, "Browser"), owner(3, "Browser"), owner(4, "Helper")],
        )]);
        let first = engine.snapshot("a".into(), vec![socket()], owners, coverage());
        assert_eq!(first.aggregates.sockets, 1);
        assert_eq!(first.aggregates.applications["Browser"], 1);
        assert_eq!(first.aggregates.applications["Helper"], 1);
        let second = engine.snapshot("b".into(), vec![socket()], HashMap::new(), coverage());
        assert_eq!(first.connections[0].id, second.connections[0].id);
        engine.snapshot("c".into(), vec![], HashMap::new(), coverage());
        let fourth = engine.snapshot("d".into(), vec![socket()], HashMap::new(), coverage());
        assert_ne!(first.connections[0].id, fourth.connections[0].id);
        assert_eq!(fourth.connections[0].country, None);
        assert_eq!(fourth.connections[0].direction, "unknown");
    }
    #[test]
    fn wire_budget_keeps_aggregates_consistent() {
        let mut engine = Engine::new(None).unwrap();
        let owners = HashMap::from([(
            1,
            (0..16)
                .map(|pid| Owner {
                    pid,
                    start_time_ticks: "8".into(),
                    name: "🦀".repeat(128),
                })
                .collect(),
        )]);
        let mut snapshot =
            engine.snapshot("a".into(), vec![socket(); MAX_SOCKETS], owners, coverage());
        let bytes = snapshot.encode_bounded().unwrap();
        assert!(bytes.len() <= MAX_LINE);
        assert!(snapshot.coverage.truncated);
        assert_eq!(
            snapshot.connections.len() + snapshot.coverage.omitted_rows,
            MAX_SOCKETS
        );
        assert_eq!(snapshot.aggregates.sockets, snapshot.connections.len());
        assert_eq!(
            snapshot.aggregates.countries["nonInternet"],
            snapshot.connections.len()
        );
    }
}
