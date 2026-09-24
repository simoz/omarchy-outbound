use crate::scope::{self, Scope};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, VecDeque},
    fs::OpenOptions,
    io::{self, Read},
    net::IpAddr,
    os::unix::fs::OpenOptionsExt,
    path::Path,
};
const MAX_DATABASE_BYTES: u64 = 64 * 1024 * 1024;
const CACHE_SIZE: usize = 8192;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub state: &'static str,
    pub build_epoch_seconds: Option<u64>,
    pub release_month: Option<String>,
    pub stale: bool,
    pub lookup_errors: usize,
}
#[derive(Deserialize)]
struct Record {
    country: Option<Country>,
}
#[derive(Deserialize)]
struct Country {
    iso_code: Option<String>,
}
pub struct Geo {
    reader: Option<maxminddb::Reader<Vec<u8>>>,
    pub status: Status,
    cache: HashMap<IpAddr, Option<String>>,
    order: VecDeque<IpAddr>,
}
impl Geo {
    pub fn load(path: Option<&Path>, now_seconds: u64) -> Self {
        let mut geo = Self {
            reader: None,
            status: Status {
                state: "missing",
                build_epoch_seconds: None,
                release_month: None,
                stale: false,
                lookup_errors: 0,
            },
            cache: HashMap::new(),
            order: VecDeque::new(),
        };
        let Some(path) = path else {
            return geo;
        };
        let result = (|| -> io::Result<maxminddb::Reader<Vec<u8>>> {
            let file = OpenOptions::new()
                .read(true)
                .custom_flags(libc::O_NONBLOCK)
                .open(path)?;
            let metadata = file.metadata()?;
            if !metadata.is_file() || metadata.len() > MAX_DATABASE_BYTES {
                return Err(io::ErrorKind::InvalidData.into());
            }
            let mut bytes = Vec::new();
            file.take(MAX_DATABASE_BYTES + 1).read_to_end(&mut bytes)?;
            if bytes.len() as u64 > MAX_DATABASE_BYTES {
                return Err(io::ErrorKind::InvalidData.into());
            }
            let reader =
                maxminddb::Reader::from_source(bytes).map_err(|_| io::ErrorKind::InvalidData)?;
            reader.verify().map_err(|_| io::ErrorKind::InvalidData)?;
            let epoch = reader.metadata().build_epoch;
            if epoch > now_seconds || epoch < 946684800 {
                return Err(io::ErrorKind::InvalidData.into());
            }
            Ok(reader)
        })();
        match result {
            Ok(reader) => {
                let epoch = reader.metadata().build_epoch;
                geo.status.state = "ready";
                geo.status.build_epoch_seconds = Some(epoch);
                geo.status.release_month = Some(month(epoch));
                geo.status.stale = now_seconds.saturating_sub(epoch) > 90 * 86400;
                geo.reader = Some(reader);
            }
            Err(e) => {
                geo.status.state = match e.kind() {
                    io::ErrorKind::NotFound => "missing",
                    io::ErrorKind::PermissionDenied => "unreadable",
                    _ => "invalid",
                }
            }
        }
        geo
    }
    pub fn lookup(&mut self, address: IpAddr) -> Option<String> {
        let address = scope::normalized(address);
        if scope::classify(address) != Scope::Public {
            return None;
        }
        if let Some(value) = self.cache.get(&address) {
            return value.clone();
        }
        let reader = self.reader.as_ref()?;
        let value = match reader.lookup(address).and_then(|v| v.decode::<Record>()) {
            Ok(record) => {
                let code = record.and_then(|r| r.country).and_then(|c| c.iso_code);
                match code {
                    Some(code)
                        if code.len() == 2
                            && code.bytes().all(|b| b.is_ascii_uppercase())
                            && code != "ZZ" =>
                    {
                        Some(code)
                    }
                    Some(code) if code != "ZZ" => {
                        self.status.lookup_errors += 1;
                        None
                    }
                    _ => None,
                }
            }
            Err(_) => {
                self.status.lookup_errors += 1;
                None
            }
        };
        if self.cache.len() == CACHE_SIZE {
            if let Some(old) = self.order.pop_front() {
                self.cache.remove(&old);
            }
        }
        self.order.push_back(address);
        self.cache.insert(address, value.clone());
        value
    }
}
fn month(epoch: u64) -> String {
    // Gregorian civil date from days since Unix epoch (400-year eras).
    let z = (epoch / 86400) as i64 + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let month = mp + if mp < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);
    format!("{year:04}-{month:02}")
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn missing_and_special_addresses_do_not_invent_countries() {
        let mut geo = Geo::load(None, 1800000000);
        assert_eq!(geo.status.state, "missing");
        assert_eq!(geo.lookup("8.8.8.8".parse().unwrap()), None);
        assert_eq!(geo.lookup("127.0.0.1".parse().unwrap()), None);
        assert!(geo.cache.is_empty());
        assert_eq!(month(0), "1970-01");
        assert_eq!(month(1709164800), "2024-02");
    }
}
