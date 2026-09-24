use std::{
    io::Write,
    process::{Child, Command, Stdio},
    time::{Duration, Instant},
};
fn start() -> Child {
    Command::new(env!("CARGO_BIN_EXE_outbound-engine"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap()
}
fn finish(mut child: Child) -> std::process::Output {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if child.try_wait().unwrap().is_some() {
            return child.wait_with_output().unwrap();
        }
        if Instant::now() >= deadline {
            child.kill().unwrap();
            let _ = child.wait();
            panic!("Backend did not exit within deadline");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}
#[test]
fn idle_eof_and_shutdown() {
    let mut child = start();
    std::thread::sleep(Duration::from_millis(50));
    assert!(child.try_wait().unwrap().is_none());
    drop(child.stdin.take());
    let output = finish(child);
    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    let mut child = start();
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"{\"version\":1,\"requestId\":\"bye\",\"command\":\"shutdown\"}\n")
        .unwrap();
    let output = finish(child);
    assert!(output.status.success());
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["kind"], "stopped");
    assert_eq!(value["requestId"], "bye");
}
#[test]
fn oversized_unterminated_and_incompatible_commands_fail_closed() {
    for input in [
        vec![b'x'; 4097],
        b"{\"version\":2,\"requestId\":\"x\",\"command\":\"snapshot\"}\n".to_vec(),
    ] {
        let mut child = start();
        child.stdin.as_mut().unwrap().write_all(&input).unwrap();
        // Keep stdin open: the oversized command must not wait for newline or EOF.
        let output = finish(child);
        assert!(!output.status.success());
        let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(value["kind"], "error");
        assert_eq!(value["fatal"], true);
        assert!(!String::from_utf8_lossy(&output.stderr).contains("requestId"));
    }
}
