"""Local tests for the explicit HTTPS traffic generator."""
import importlib.util
from pathlib import Path
import socket
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("traffic", Path(__file__).resolve().parents[1] / "tools/test_connections.py")
traffic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(traffic)


class ConnectionsTests(unittest.TestCase):
    def test_peer_close_and_cancellation_stop_holding(self):
        class LocalSocket:
            def __init__(self, sock):
                self.sock = sock
            def pending(self):
                return 0
            def fileno(self):
                return self.sock.fileno()
            def recv(self, length):
                return self.sock.recv(length)
        left, right = socket.socketpair()
        with left, right:
            right.shutdown(socket.SHUT_WR)
            traffic.hold_connection(LocalSocket(left), threading.Event(), time.monotonic() + 2)
            stop = threading.Event()
            stop.set()
            traffic.hold_connection(LocalSocket(left), stop, time.monotonic() + 2)

    def test_worker_sends_head_and_closes_after_stop(self):
        tcp = MagicMock()
        connection = MagicMock()
        connection.__enter__.return_value = connection
        connection.getpeername.return_value = ("192.0.2.1", 443)
        context = MagicMock()
        context.wrap_socket.return_value = connection
        stop = threading.Event()
        with patch.object(traffic.socket, "create_connection", return_value=tcp), patch.object(traffic, "hold_connection", side_effect=lambda *args: stop.set()):
            count = traffic.worker("example.test", 30, 20, stop, context, lambda message: None)
        self.assertEqual(count, 1)
        self.assertTrue(connection.sendall.call_args.args[0].startswith(b"HEAD / HTTP/1.1\r\nHost: example.test\r\n"))
        self.assertEqual(context.wrap_socket.call_args.kwargs["server_hostname"], "example.test")
        connection.__exit__.assert_called_once()
        tcp.__exit__.assert_called_once()


if __name__ == "__main__":
    unittest.main()
