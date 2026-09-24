mod common;
use outbound_engine::owners;
use std::{
    collections::HashSet,
    fs,
    os::unix::fs::{PermissionsExt, symlink},
    time::{Duration, Instant},
};

#[test]
fn bounded_shared_owners_races_and_permissions() {
    assert_ne!(unsafe { libc::geteuid() }, 0, "Run tests without root");
    let temp = common::Temp::new();
    for pid in 1..=20 {
        let path = temp.0.join(pid.to_string());
        fs::create_dir_all(path.join("fd")).unwrap();
        fs::write(
            path.join("stat"),
            format!("{pid} (worker) S {} {pid} 0", vec!["0"; 18].join(" ")),
        )
        .unwrap();
        fs::write(path.join("comm"), "worker\n").unwrap();
        symlink("socket:[42]", path.join("fd/3")).unwrap();
        symlink("socket:[42]", path.join("fd/4")).unwrap(); // A duplicate fd is one owner.
    }
    fs::create_dir(temp.0.join("21")).unwrap(); // A process disappears before stat.
    fs::set_permissions(temp.0.join("20/fd"), fs::Permissions::from_mode(0o0)).unwrap();
    let (rows, c) = owners::scan(
        &temp.0,
        &HashSet::from([42]),
        Instant::now() + Duration::from_secs(1),
    );
    fs::set_permissions(temp.0.join("20/fd"), fs::Permissions::from_mode(0o700)).unwrap();
    assert_eq!(rows[&42].len(), 16);
    assert_eq!(c.owners_omitted, 3);
    assert_eq!(c.denied, 1);
    assert_eq!(c.races, 1);
    let (rows, c) = owners::scan(&temp.0, &HashSet::from([42]), Instant::now());
    assert!(rows.is_empty());
    assert!(c.timed_out);
}
