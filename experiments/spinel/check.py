"""Exercise the compiled probe with real loopback sockets and synthetic MMDB."""

import contextlib
import json
import os
from pathlib import Path
import selectors
import socket
import struct
import subprocess
import tempfile
import unittest


def text(value):
    encoded = value.encode()
    assert len(encoded) < 29
    return bytes([0x40 | len(encoded)]) + encoded


def mapping(items):
    return bytes([0xE0 | len(items)]) + b"".join(
        text(key) + value for key, value in items
    )


def database():
    # Same original, synthetic one-node format used by backend/tests/geo.rs.
    def small(value):
        return b"\xa2" + struct.pack(">H", value)

    return (
        bytes([0, 0, 17, 0, 0, 17])
        + bytes(16)
        + mapping([("country", mapping([("iso_code", text("IT"))]))])
        + b"\xab\xcd\xefMaxMind.com"
        + mapping(
            [
                ("binary_format_major_version", small(2)),
                ("binary_format_minor_version", small(0)),
                ("build_epoch", b"\x08\x02" + struct.pack(">Q", 1704067200)),
                ("database_type", text("Outbound-Synthetic-Country")),
                ("description", mapping([("en", text("Synthetic test data"))])),
                ("ip_version", small(6)),
                ("languages", b"\x01\x04" + text("en")),
                ("node_count", b"\xc1\x01"),
                ("record_size", small(24)),
            ]
        )
    )


class ProbeTest(unittest.TestCase):
    def setUp(self):
        self.resources = contextlib.ExitStack()
        self.addCleanup(self.resources.close)
        temp = self.resources.enter_context(tempfile.TemporaryDirectory())
        self.db = Path(temp) / "synthetic.mmdb"
        self.db.write_bytes(database())
        self.process = subprocess.Popen(
            ["./probe"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0,
        )
        self.addCleanup(self.stop)

    def stop(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.communicate(timeout=5)

    def response(self, data):
        self.process.stdin.write(data)
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            while not output.endswith(b"\n"):
                self.assertTrue(selector.select(5), "probe response timed out")
                byte = self.process.stdout.read(1)
                self.assertTrue(byte, "probe exited before responding")
                output.extend(byte)
                self.assertLess(len(output), 4096)
        return json.loads(output)

    def request(self, family):
        address = "127.0.0.1" if family == 4 else "::1"
        af = socket.AF_INET if family == 4 else socket.AF_INET6
        server = self.resources.enter_context(socket.socket(af, socket.SOCK_STREAM))
        server.settimeout(3)
        server.bind((address, 0))
        server.listen(1)
        client = self.resources.enter_context(socket.socket(af, socket.SOCK_STREAM))
        client.settimeout(3)
        client.connect(server.getsockname())
        accepted, _ = server.accept()
        self.resources.enter_context(accepted)
        return {
            "command": "probe",
            "requestId": 'unicode-è-"-\\',
            "family": family,
            "localPort": client.getsockname()[1],
            "remotePort": server.getsockname()[1],
            "ownerPid": os.getpid(),
            "database": str(self.db),
        }

    def send(self, request):
        return self.response((json.dumps(request) + "\n").encode())

    def test_ipv4_ipv6_ownership_geoip_and_repeated_json(self):
        for family in (4, 6):
            request = self.request(family)
            for _ in range(3):
                response = self.send(request)
                self.assertEqual(response["requestId"], request["requestId"])
                self.assertEqual(response["family"], family)
                self.assertGreater(response["inode"], 0)
                self.assertTrue(response["ownerVerified"])
                self.assertEqual(response["syntheticCountry"], "IT")

    def test_wrong_owner_is_not_attributed(self):
        request = self.request(4)
        request["ownerPid"] = self.process.pid
        response = self.send(request)
        self.assertGreater(response["inode"], 0)
        self.assertFalse(response["ownerVerified"])

    def test_listening_socket_is_not_an_established_connection(self):
        request = self.request(4)
        # The server's listening port cannot be the client's local endpoint.
        request["localPort"] = request["remotePort"]
        response = self.send(request)
        self.assertEqual(response["inode"], 0)
        self.assertFalse(response["ownerVerified"])

    def test_missing_and_corrupt_database(self):
        request = self.request(4)
        request["database"] += ".missing"
        self.assertEqual(self.send(request)["syntheticCountry"], "openError")
        self.db.write_bytes(b"invalid")
        request["database"] = str(self.db)
        self.assertEqual(self.send(request)["syntheticCountry"], "openError")

    def test_invalid_json_and_command_then_recovery(self):
        self.assertEqual(self.response(b"{\n")["error"], "invalidJson")
        self.assertEqual(self.send({"command": "unknown"})["error"], "invalidCommand")
        request = self.request(4)
        self.assertTrue(self.send(request)["ownerVerified"])
        request["family"] = 99
        self.assertEqual(self.send(request)["error"], "invalidProbe")

    def test_oversized_frame_exits(self):
        self.assertEqual(self.response(b" " * 4097)["error"], "invalidFrame")
        self.assertEqual(self.process.wait(timeout=5), 0)

    def test_unterminated_frame_exits(self):
        self.process.stdin.write(b"{}")
        self.process.stdin.close()
        self.process.stdin = None
        out, err = self.process.communicate(timeout=5)
        self.assertEqual(json.loads(out)["error"], "invalidFrame")
        self.assertEqual(err, b"")
        self.assertEqual(self.process.returncode, 0)

    def test_shutdown_and_eof(self):
        self.process.stdin.write(b'{"command":"shutdown"}\n')
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.process.stdout.read(), b"")
        result = subprocess.run(["./probe"], input=b"", capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
