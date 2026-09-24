use outbound_engine::engine::Engine;
use std::{
    net::{TcpListener, TcpStream},
    process::Command,
};

#[test]
#[ignore = "Requires real Linux netlink, IPv4/IPv6 loopback and ss; run explicitly"]
fn controlled_sockets_match_ss_and_own_process() {
    assert_ne!(unsafe { libc::geteuid() }, 0);
    let process_status = std::fs::read_to_string("/proc/self/status").unwrap();
    let capabilities = process_status
        .lines()
        .find_map(|line| line.strip_prefix("CapEff:"))
        .unwrap()
        .trim();
    assert_eq!(
        u64::from_str_radix(capabilities, 16).unwrap(),
        0,
        "Run without effective capabilities"
    );
    let mut engine = Engine::new(None).unwrap();
    for address in ["127.0.0.1:0", "[::1]:0"] {
        let listener = TcpListener::bind(address).unwrap();
        let server = listener.local_addr().unwrap();
        let client = TcpStream::connect(server).unwrap();
        let (_peer, _) = listener.accept().unwrap();
        let client_port = client.local_addr().unwrap().port();
        let sample = engine.sample("test".into());
        assert!(sample.coverage.ipv4.is_none());
        assert!(sample.coverage.ipv6.is_none());
        let rows: Vec<_> = sample
            .connections
            .iter()
            .filter(|c| {
                (c.local.port == client_port && c.remote.port == server.port())
                    || (c.local.port == server.port() && c.remote.port == client_port)
            })
            .collect();
        assert_eq!(rows.len(), 2);
        for row in &rows {
            assert_eq!(row.state, "ESTABLISHED");
            assert_eq!(row.uid, unsafe { libc::getuid() });
            assert_eq!(row.scope, outbound_engine::scope::Scope::Loopback);
            assert!(row.owners.iter().any(|o| o.pid == std::process::id()));
            assert_eq!(row.country, None);
            assert_eq!(row.direction, "unknown");
        }
        let output = Command::new("ss")
            .args([
                "-H",
                "-n",
                "-t",
                "-p",
                if server.is_ipv4() { "-4" } else { "-6" },
                "state",
                "established",
                &format!(
                    "( sport = :{} or dport = :{} )",
                    server.port(),
                    server.port()
                ),
            ])
            .output()
            .unwrap();
        assert!(output.status.success());
        let reference = String::from_utf8(output.stdout).unwrap();
        assert_eq!(reference.lines().count(), 2);
        assert!(
            reference
                .lines()
                .all(|l| l.contains(&format!("pid={},", std::process::id())))
        );
        let ids: Vec<_> = rows.iter().map(|r| r.id.clone()).collect();
        let next = engine.sample("next".into());
        assert!(
            ids.iter()
                .all(|id| next.connections.iter().any(|r| &r.id == id))
        );
        // A connection opened and closed entirely between snapshots is not history.
        let short = TcpStream::connect(server).unwrap();
        let (short_peer, _) = listener.accept().unwrap();
        let short_port = short.local_addr().unwrap().port();
        drop(short);
        drop(short_peer);
        let after = engine.sample("after".into());
        assert!(
            !after
                .connections
                .iter()
                .any(|c| c.local.port == short_port && c.state == "ESTABLISHED")
        );
    }
}

#[test]
#[ignore = "Requires native kernel socket diagnostics; run explicitly"]
fn executable_streams_requested_snapshots_then_exits_on_eof() {
    use std::{
        io::{BufRead, BufReader, Write},
        process::Stdio,
    };
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
    let (_peer, _) = listener.accept().unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_outbound-engine"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    let mut output = BufReader::new(child.stdout.take().unwrap());
    let mut session = None;
    for sequence in 1..=2 {
        writeln!(
            input,
            "{{\"version\":1,\"requestId\":\"r-{sequence}\",\"command\":\"snapshot\"}}"
        )
        .unwrap();
        input.flush().unwrap();
        let mut line = String::new();
        assert!(output.read_line(&mut line).unwrap() <= outbound_engine::engine::MAX_LINE);
        let value: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(value["kind"], "snapshot");
        assert_eq!(value["requestId"], format!("r-{sequence}"));
        assert_eq!(value["sequence"], sequence);
        assert_ne!(value["status"], "error");
        if let Some(before) = &session {
            assert_eq!(before, &value["session"]);
        }
        session = Some(value["session"].clone());
        let rows = value["connections"].as_array().unwrap();
        assert_eq!(value["aggregates"]["sockets"], rows.len());
        assert!(
            rows.iter()
                .any(|r| r["local"]["port"] == client.local_addr().unwrap().port())
        );
    }
    drop(input);
    let mut rest = String::new();
    assert_eq!(output.read_line(&mut rest).unwrap(), 0);
    assert!(child.wait().unwrap().success());
}
