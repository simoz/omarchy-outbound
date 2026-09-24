mod common;
use outbound_engine::geo::Geo;
use std::{fs, os::unix::fs::PermissionsExt};

// A tiny original synthetic MMDB; no provider data or live IP-country assertions.
fn text(value: &str) -> Vec<u8> {
    assert!(value.len() < 29);
    let mut v = vec![0x40 | value.len() as u8];
    v.extend(value.as_bytes());
    v
}
fn map(items: Vec<(&str, Vec<u8>)>) -> Vec<u8> {
    let mut v = vec![0xe0 | items.len() as u8];
    for (key, value) in items {
        v.extend(text(key));
        v.extend(value);
    }
    v
}
fn small(value: u16) -> Vec<u8> {
    let mut v = vec![0xa2];
    v.extend(value.to_be_bytes());
    v
}
fn database(code: &str, epoch: u64) -> Vec<u8> {
    let mut bytes = vec![0, 0, 17, 0, 0, 17]; // One 24-bit node; both branches reference data.
    bytes.extend([0; 16]);
    bytes.extend(map(vec![("country", map(vec![("iso_code", text(code))]))]));
    bytes.extend(b"\xab\xcd\xefMaxMind.com");
    let mut build = vec![8, 2];
    build.extend(epoch.to_be_bytes());
    bytes.extend(map(vec![
        ("binary_format_major_version", small(2)),
        ("binary_format_minor_version", small(0)),
        ("build_epoch", build),
        ("database_type", text("Outbound-Synthetic-Country")),
        (
            "description",
            map(vec![("en", text("Synthetic test data"))]),
        ),
        ("ip_version", small(6)),
        ("languages", [vec![1, 4], text("en")].concat()),
        ("node_count", vec![0xc1, 1]),
        ("record_size", small(24)),
    ]));
    bytes
}
#[test]
fn local_lookup_age_validation_and_no_special_geolocation() {
    let temp = common::Temp::new();
    let path = temp.0.join("synthetic.mmdb");
    fs::write(&path, database("IT", 1704067200)).unwrap();
    maxminddb::Reader::open_readfile(&path)
        .unwrap()
        .verify()
        .unwrap();
    let mut geo = Geo::load(Some(&path), 1704067201);
    assert_eq!(geo.status.state, "ready");
    assert_eq!(geo.status.release_month.as_deref(), Some("2024-01"));
    assert!(!geo.status.stale);
    for ip in ["8.8.8.8", "::ffff:8.8.8.8", "2001:4860::8888"] {
        assert_eq!(geo.lookup(ip.parse().unwrap()).as_deref(), Some("IT"));
    }
    for ip in ["127.0.0.1", "192.0.2.1", "fc00::1", "2001:db8::1"] {
        assert_eq!(geo.lookup(ip.parse().unwrap()), None);
    }
    assert!(Geo::load(Some(&path), 1800000000).status.stale);
    assert_eq!(Geo::load(Some(&path), 1600000000).status.state, "invalid");
    for code in ["ZZ", "bad"] {
        fs::write(&path, database(code, 1704067200)).unwrap();
        let mut geo = Geo::load(Some(&path), 1800000000);
        assert_eq!(geo.lookup("8.8.8.8".parse().unwrap()), None);
        assert_eq!(geo.status.lookup_errors, usize::from(code == "bad"));
    }
    fs::set_permissions(&path, fs::Permissions::from_mode(0o0)).unwrap();
    let unreadable = Geo::load(Some(&path), 1800000000).status.state;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    assert_eq!(unreadable, "unreadable");
    fs::File::create(&path)
        .unwrap()
        .set_len(64 * 1024 * 1024 + 1)
        .unwrap();
    assert_eq!(Geo::load(Some(&path), 1800000000).status.state, "invalid");
    fs::write(&path, b"corrupt").unwrap();
    assert_eq!(Geo::load(Some(&path), 1800000000).status.state, "invalid");
    fs::remove_file(&path).unwrap();
    assert_eq!(Geo::load(Some(&path), 1800000000).status.state, "missing");
}
