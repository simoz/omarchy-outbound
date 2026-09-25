"""Check the production command envelope against the compiled Ruby driver."""

import json
import subprocess
import unittest


class ProtocolTest(unittest.TestCase):
    def run_driver(self, data):
        result = subprocess.run(
            ["./protocol-probe"], input=data, capture_output=True, timeout=5
        )
        self.assertEqual(result.stderr, b"")
        return result.returncode, [json.loads(line) for line in result.stdout.splitlines()]

    def error(self, data, code):
        status, rows = self.run_driver(data)
        self.assertNotEqual(status, 0)
        self.assertEqual(rows, [{"version": 1, "kind": "error", "requestId": None,
                                "code": code, "fatal": True}])

    def test_eof_and_shutdown(self):
        self.assertEqual(self.run_driver(b""), (0, []))
        command = b'{"version":1,"requestId":"stop-1","command":"shutdown"}\n'
        self.assertEqual(self.run_driver(command + b"bad\n"), (0, [
            {"version": 1, "kind": "stopped", "requestId": "stop-1"}
        ]))

    def test_repeated_commands(self):
        command = b'{"version":1,"requestId":"sample_1","command":"snapshot"}\n'
        self.assertEqual(self.run_driver(command * 3), (0, [
            {"experiment": "protocol", "requestId": "sample_1"}
        ] * 3))

    def test_frame_limits(self):
        command = b'{"version":1,"requestId":"x","command":"snapshot"}'
        self.assertEqual(self.run_driver(command + b" " * (4095 - len(command)) + b"\n")[0], 0)
        for data in (b" " * 4097, command + b" " * (4096 - len(command)) + b"\n"):
            self.error(data, "commandTooLarge")
        for data in (command, b" " * 4096):
            self.error(data, "unterminatedCommand")

    def test_oversized_input_without_eof(self):
        process = subprocess.Popen(["./protocol-probe"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            process.stdin.write(b" " * 4097)
            process.stdin.flush()
            self.assertNotEqual(process.wait(timeout=5), 0)
            self.assertEqual(json.loads(process.stdout.readline())["code"], "commandTooLarge")
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)

    def test_depth_and_invalid_json(self):
        self.error(b"[" * 9 + b"0" + b"]" * 9 + b"\n", "commandTooDeep")
        for data in (b"[" * 8 + b"0" + b"]" * 8 + b"\n", b"}\n", b"{\n",
                     b"[]\n", b"null\n", b"{}\n", b"\xff\n"):
            self.error(data, "invalidCommand")

    def test_duplicate_and_unknown_fields(self):
        for extra in ('"version":1', '"vers\\u0069on":1', '"requestId":"x"',
                      '"command":"snapshot"', '"extra":null'):
            data = '{"version":1,"requestId":"x","command":"snapshot",' + extra + '}\n'
            self.error(data.encode(), "invalidCommand")

    def test_unsigned_version_syntax(self):
        for value in (b"-0", b"-0.0", b"1e0", b"18446744073709551617"):
            self.error(b'{"version":' + value +
                       b',"requestId":"x","command":"snapshot"}\n', "invalidCommand")

    def test_schema_types_and_ids(self):
        base = {"version": 1, "requestId": "x", "command": "snapshot"}
        for field, values, code in (
            ("version", [None, True, "1", 1.0, -1, 256], "invalidCommand"),
            ("version", [0, 2, 255], "unsupportedVersion"),
            ("requestId", [None, 1, [], {}], "invalidCommand"),
            ("requestId", ["", "x" * 65, "è", "x\n", "x y", '[]{}"\\'], "invalidRequestId"),
            ("command", [None, 1, "other", [], {}], "invalidCommand"),
        ):
            for value in values:
                with self.subTest(field=field, value=value):
                    self.error((json.dumps(base | {field: value}) + "\n").encode(), code)
        for field in base:
            self.error((json.dumps({k: v for k, v in base.items() if k != field}) + "\n").encode(),
                       "invalidCommand")
        base["requestId"] = "aZ09_-" + "x" * 58
        self.assertEqual(self.run_driver((json.dumps(base) + "\n").encode())[0], 0)

    def test_fatal_input_does_not_execute_following_command(self):
        self.error(b'{}\n{"version":1,"requestId":"stop","command":"shutdown"}\n',
                   "invalidCommand")

    def test_invalid_unicode_strings(self):
        for value in (b"\xff", b"\xc0\xaf", b"\xed\xa0\x80", b"\\ud800", b"\\udc00"):
            self.error(b'{"version":1,"requestId":"' + value +
                       b'","command":"snapshot"}\n', "invalidCommand")

    def test_escaped_keys(self):
        data = b'{"vers\\u0069on":1,"requestId":"x","command":"snapshot"}\n'
        self.assertEqual(self.run_driver(data)[0], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
