"""Generate a small, bounded set of real HTTPS connections for Outbound."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import select
import socket
import ssl
import threading
import time

DEFAULT_HOSTS = ("www.python.org", "www.wikipedia.org", "github.com", "www.kernel.org", "www.cloudflare.com")
CONNECT_TIMEOUT = 5
RECONNECT_DELAY = 5


def hold_connection(connection, stop, deadline):
    # Servers may close keep-alive connections early. Detect EOF so the worker
    # reconnects instead of claiming a closed socket is still being held open.
    received = 0
    while not stop.is_set() and time.monotonic() < deadline:
        if connection.pending() or select.select([connection], [], [], 0.2)[0]:
            chunk = connection.recv(4096)
            if not chunk:
                return
            received += len(chunk)
            if received > 65536:
                raise OSError("HEAD response exceeded 64 KiB")


def worker(host, duration, hold, stop, context, report):
    deadline = time.monotonic() + duration
    connections = 0
    while not stop.is_set() and time.monotonic() < deadline:
        try:
            with socket.create_connection((host, 443), timeout=CONNECT_TIMEOUT) as tcp:
                with context.wrap_socket(tcp, server_hostname=host) as connection:
                    if stop.is_set():
                        break
                    connection.sendall(
                        f"HEAD / HTTP/1.1\r\nHost: {host}\r\nUser-Agent: Outbound-Connection-Test/1.0\r\nConnection: keep-alive\r\n\r\n".encode("ascii")
                    )
                    connections += 1
                    report(f"Connected: {host} ({connection.getpeername()[0]})")
                    hold_connection(connection, stop, min(deadline, time.monotonic() + hold))
        except OSError as error:
            report(f"Unavailable: {host}: {error}")
        stop.wait(max(0, min(RECONNECT_DELAY, deadline - time.monotonic())))
    return connections


def main():
    parser = argparse.ArgumentParser(description="Open real HTTPS connections for the Outbound UI; Ctrl+C closes them.")
    parser.add_argument("--duration", type=int, default=120, help="Run time in seconds (1–600; default: 120)")
    parser.add_argument("--hold", type=int, default=20, help="Maximum hold per connection (1–60; default: 20)")
    parser.add_argument("--host", action="append", help="HTTPS hostname; repeat for up to 8 targets (replaces defaults)")
    args = parser.parse_args()
    hosts = list(dict.fromkeys(args.host or DEFAULT_HOSTS))
    if not 1 <= args.duration <= 600 or not 1 <= args.hold <= 60:
        parser.error("Use duration 1–600 and hold 1–60 seconds")
    if len(hosts) > 8 or any(not host or len(host) > 253 or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" for c in host) for host in hosts):
        parser.error("Use up to 8 plain HTTPS hostnames, without URLs or paths")
    stop = threading.Event()
    lock = threading.Lock()
    context = ssl.create_default_context()
    def report(message):
        with lock:
            print(message, flush=True)
    print(f"Opening {len(hosts)} HTTPS targets for {args.duration}s. Filter Outbound by python3.")
    print("Only HEAD requests; no page downloads. GeoIP countries depend on DNS/CDN routing. Ctrl+C stops.")
    with ThreadPoolExecutor(max_workers=len(hosts)) as pool:
        jobs = [pool.submit(worker, host, args.duration, args.hold, stop, context, report) for host in hosts]
        try:
            while not all(job.done() for job in jobs):
                stop.wait(0.2)
        except KeyboardInterrupt:
            print("Closing test connections…", flush=True)
        finally:
            stop.set()
    total = sum(job.result() for job in jobs)
    print(f"Finished: {total} connections opened; all test sockets closed.")
    return 0 if total else 1


if __name__ == "__main__":
    raise SystemExit(main())
