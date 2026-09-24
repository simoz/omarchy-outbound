"""Local fixtures and controlled sockets; never report unrelated connections."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import selectors
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "backend/ruby/build"
ENGINE = BUILD / "outbound-engine"
spec = importlib.util.spec_from_file_location("spinel_fixture", ROOT / "experiments/spinel/check.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class BackendTest(unittest.TestCase):
    def setUp(self):
        self.resources = contextlib.ExitStack()
        self.addCleanup(self.resources.close)
        self.temp = Path(self.resources.enter_context(tempfile.TemporaryDirectory()))
        self.database = self.temp / "synthetic.mmdb"
        self.database.write_bytes(fixture.database())

    def run_engine(self, *args, data=b""):
        return subprocess.run([str(ENGINE), *map(str, args)], input=data, capture_output=True, timeout=8)

    def test_ruby_units_and_proc_fixtures(self):
        proc = self.temp / "proc"
        proc.mkdir()
        for pid in range(1, 19):
            folder = proc / str(pid)
            (folder / "fd").mkdir(parents=True)
            (folder / "stat").write_text(f"{pid} (name with ) brackets) " + " ".join(["S"] + ["0"] * 18 + ["123"]))
            (folder / "comm").write_text("船🦀\x00name\n")
            (folder / "fd/3").symlink_to("socket:[7]")
            (folder / "fd/4").symlink_to("socket:[7]")
        (proc / "19").mkdir()
        (proc / "19/stat").write_bytes(b"")
        for code in ("ZZ", "bad"):
            replacement = bytes([0x40 + len(code)]) + code.encode()
            (self.temp / f"{code}.mmdb").write_bytes(fixture.database().replace(b"\x42IT", replacement))
        original = fixture.mapping([("country", fixture.mapping([("iso_code", fixture.text("IT"))]))])
        wrong_type = fixture.mapping([("country", fixture.text("bad"))])
        (self.temp / "type.mmdb").write_bytes(fixture.database().replace(original, wrong_type))
        result = subprocess.run([str(BUILD / "unit-tests"), str(proc), str(self.database), str(self.temp)],
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn(b"PASS Ruby", result.stdout)

    def test_database_validation(self):
        result = self.run_engine("--check-database", "--database", self.database)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout)["state"], "ready")
        valid = self.database.read_bytes()
        for content in (b"invalid", valid.replace(b"Country", b"NotGeo!"),
                        bytes(6) + valid[6:], valid[:6] + valid[6:].replace(b"\xe1", b"\xff", 1)):
            self.database.write_bytes(content)
            result = self.run_engine("--check-database", "--database", self.database)
            self.assertNotEqual(result.returncode, 0)
        self.database.write_bytes(valid)
        self.database.chmod(0)
        self.assertNotEqual(self.run_engine("--check-database", "--database", self.database).returncode, 0)
        self.database.chmod(0o600)
        self.database.write_bytes(b"")
        with self.database.open("wb") as file:
            file.truncate(64 * 1024 * 1024 + 1)
        self.assertNotEqual(self.run_engine("--check-database", "--database", self.database).returncode, 0)
        fifo = self.temp / "fifo"
        os.mkfifo(fifo)
        self.assertNotEqual(self.run_engine("--check-database", "--database", fifo).returncode, 0)

    def test_eof_shutdown_and_fatal_protocol(self):
        self.assertEqual(self.run_engine().returncode, 0)
        result = self.run_engine(data=b'{"version":1,"requestId":"stop","command":"shutdown"}\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), {"version": 1, "kind": "stopped", "requestId": "stop"})
        for data, code in ((b"{}\n", "invalidCommand"), (b"{}", "unterminatedCommand"),
                           (b" " * 4097, "commandTooLarge")):
            result = self.run_engine(data=data)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)["code"], code)

    def test_closed_stdout_exits_cleanly(self):
        process = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            process.stdout.close()
            process.stdin.write(b'{"version":1,"requestId":"sample","command":"snapshot"}\n')
            process.stdin.flush()
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertEqual(process.stderr.read(), b"")
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            process.stdin.close()
            process.stderr.close()

    def start(self, executable):
        process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, bufsize=0)
        def stop():
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)
        self.addCleanup(stop)
        return process

    def snapshot(self, process, request_id):
        process.stdin.write((json.dumps({"version": 1, "requestId": request_id, "command": "snapshot"}) + "\n").encode())
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while not output.endswith(b"\n"):
                self.assertTrue(selector.select(5), "snapshot timed out")
                data = os.read(process.stdout.fileno(), 65536)
                self.assertTrue(data, "backend exited before snapshot")
                output.extend(data)
                self.assertLessEqual(len(output), 2 * 1024 * 1024)
        self.assertTrue(output.isascii())
        # Validate the actual UI schema without dumping observed socket data.
        script = "const fs=require('fs'),vm=require('vm');const p={};vm.createContext(p);vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),p);const s=fs.readFileSync(0,'utf8');p.parse(s,JSON.parse(s).requestId,null,0);"
        validation = subprocess.run(["node", "-e", script, str(ROOT / "Protocol.js")],
                                    input=output, capture_output=True, timeout=5)
        self.assertEqual(validation.returncode, 0, "UI protocol rejected snapshot")
        result = json.loads(output)
        self.assertIsNone(result["coverage"]["ipv4"], "IPv4 dump failed")
        self.assertIsNone(result["coverage"]["ipv6"], "IPv6 dump failed")
        return result

    def test_controlled_ipv4_ipv6_ownership_and_rust_comparison(self):
        controlled = []
        for family, address in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
            server = self.resources.enter_context(socket.socket(family, socket.SOCK_STREAM))
            server.bind((address, 0))
            server.listen(1)
            server.settimeout(3)
            client = self.resources.enter_context(socket.socket(family, socket.SOCK_STREAM))
            client.settimeout(3)
            client.connect(server.getsockname())
            accepted, _ = server.accept()
            self.resources.enter_context(accepted)
            controlled.append((address, client.getsockname()[1], server.getsockname()[1]))
        ruby = self.start(ENGINE)
        first = self.snapshot(ruby, "first")
        second = self.snapshot(ruby, "second")
        self.assertEqual(second["session"], first["session"])
        self.assertEqual(second["sequence"], first["sequence"] + 1)
        rust = os.environ.get("OUTBOUND_RUST_BACKEND")
        reference = self.snapshot(self.start(rust), "rust") if rust else None
        for address, local_port, remote_port in controlled:
            def find(snapshot):
                rows = [row for row in snapshot["connections"]
                        if row["local"] == {"address": address, "port": local_port}
                        and row["remote"] == {"address": address, "port": remote_port}]
                self.assertEqual(len(rows), 1, "controlled endpoint missing or duplicated")
                return rows[0]
            row = find(first)
            self.assertEqual(row["state"], "ESTABLISHED")
            self.assertEqual(row["scope"], "loopback")
            self.assertIsNone(row["country"])
            self.assertIn(os.getpid(), [o["pid"] for o in row["owners"]])
            self.assertEqual(row["id"], find(second)["id"])
            if reference:
                other = find(reference)
                for key in ("family", "local", "remote", "state", "uid", "owners", "scope", "direction", "country"):
                    self.assertEqual(row[key], other[key], f"controlled row differs: {key}")
            self.assertFalse(any(r["state"] == "LISTEN" for r in first["connections"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
