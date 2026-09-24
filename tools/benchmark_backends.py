"""Compare local collectors on controlled loopback load; print only metrics."""

import argparse
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import resource
import selectors
import socket
import statistics
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MAX_LINE = 2 * 1024 * 1024


def metrics(pid):
    root = Path(f"/proc/{pid}")
    fields = (root / "stat").read_text().rsplit(")", 1)[1].split()
    status = {}
    for line in (root / "status").read_text().splitlines():
        key, value = line.split(":", 1)
        if key in ("VmRSS", "VmHWM"):
            status[key] = int(value.split()[0])
    return {
        "cpu_ms": (int(fields[11]) + int(fields[12])) * 1000 / os.sysconf("SC_CLK_TCK"),
        "rss_kib": status["VmRSS"],
        "peak_rss_kib": status["VmHWM"],
        "fds": sum(1 for _ in (root / "fd").iterdir()),
    }


@contextlib.contextmanager
def controlled_sockets(pairs):
    # Two reusable listeners keep the fd requirement at 2 * pairs + 2.
    with contextlib.ExitStack() as stack:
        endpoints = set()
        for family, address in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
            server = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
            server.settimeout(3)
            server.bind((address, 0))
            server.listen(1)
            for _ in range(pairs // 2):
                client = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
                # These payload-free test sockets should not leave TIME_WAIT
                # rows behind and inflate later scenarios after cleanup.
                client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                client.settimeout(3)
                client.connect(server.getsockname())
                accepted, _ = server.accept()
                stack.enter_context(accepted)
                accepted.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                local = client.getsockname()[1]
                remote = server.getsockname()[1]
                endpoints.add((address, local, remote))
                endpoints.add((address, remote, local))
        yield endpoints


class Collector:
    def __init__(self, binary):
        self.process = subprocess.Popen(
            [str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, bufsize=0,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.session = None
        self.sequence = 0

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.communicate(timeout=5)
        self.selector.close()

    def sample(self, request_id, endpoints):
        request = {"version": 1, "requestId": request_id, "command": "snapshot"}
        started = time.perf_counter()
        self.process.stdin.write((json.dumps(request) + "\n").encode())
        wire = bytearray()
        deadline = time.monotonic() + 5
        while not wire.endswith(b"\n"):
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise RuntimeError("Collector exceeded the five-second UI watchdog")
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise RuntimeError("Collector exited before completing a snapshot")
            wire.extend(data)
            if len(wire) > MAX_LINE:
                raise RuntimeError("Collector exceeded the wire budget")
        elapsed = (time.perf_counter() - started) * 1000
        if not wire.isascii() or wire.count(b"\n") != 1:
            raise RuntimeError("Collector returned invalid framing")
        snapshot = json.loads(wire)
        coverage = snapshot["coverage"]
        if (snapshot["kind"] != "snapshot" or snapshot["requestId"] != request_id
                or (self.session and self.session != snapshot["session"])
                or snapshot["sequence"] <= self.sequence
                or coverage["ipv4"] is not None or coverage["ipv6"] is not None):
            raise RuntimeError("Collector returned incomplete or stale socket coverage")
        self.session = snapshot["session"]
        self.sequence = snapshot["sequence"]
        found = set()
        for row in snapshot["connections"]:
            local, remote = row["local"], row["remote"]
            endpoint = (local["address"], local["port"], remote["port"])
            if endpoint in endpoints and remote["address"] == local["address"]:
                if (row["state"] != "ESTABLISHED" or row["scope"] != "loopback"
                        or row["country"] is not None
                        or not any(owner["pid"] == os.getpid() for owner in row["owners"])):
                    raise RuntimeError("Controlled socket attribution is incorrect")
                found.add(endpoint)
        if found != endpoints:
            raise RuntimeError("Controlled sockets are missing from the snapshot")
        return elapsed, wire, snapshot

    def idle(self, seconds):
        before = metrics(self.process.pid)
        if self.selector.select(seconds):
            raise RuntimeError("Collector wrote or exited without a request during idle")
        after = metrics(self.process.pid)
        return round(after["cpu_ms"] - before["cpu_ms"], 3)


def validate_ui(wire):
    # Validation runs after timing, without saving or printing the snapshot.
    script = """
const fs = require('fs'), vm = require('vm'), p = {};
vm.createContext(p);
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), p);
const wire = fs.readFileSync(0, 'utf8');
p.parse(wire, JSON.parse(wire).requestId, null, 0);
"""
    result = subprocess.run(
        ["node", "-e", script, str(ROOT / "Protocol.js")], input=wire,
        capture_output=True, timeout=5,
    )
    if result.returncode:
        raise RuntimeError("The UI protocol validator rejected the snapshot")


def measure(binary, endpoints, samples, warmup, idle_seconds):
    collector = Collector(binary)
    try:
        first_ms, _, _ = collector.sample("first", endpoints)
        for i in range(warmup):
            collector.sample(f"warmup-{i}", endpoints)
        before = metrics(collector.process.pid)
        latency, rss, fds, sizes, rows, limited = [], [], [], [], [], 0
        for i in range(samples):
            elapsed, wire, snapshot = collector.sample(f"sample-{i}", endpoints)
            latency.append(elapsed)
            current = metrics(collector.process.pid)
            rss.append(current["rss_kib"])
            fds.append(current["fds"])
            sizes.append(len(wire))
            rows.append(len(snapshot["connections"]))
            coverage = snapshot["coverage"]
            limited += int(coverage["truncated"] or coverage["processes"]["timedOut"]
                           or coverage["processes"]["scanLimited"])
        after = metrics(collector.process.pid)
        validate_ui(wire)
        idle_cpu_ms = collector.idle(idle_seconds)
        ordered = sorted(latency)
        return {
            "first_snapshot_ms": round(first_ms, 3),
            "median_ms": round(statistics.median(latency), 3),
            "p95_ms": round(ordered[math.ceil(len(ordered) * .95) - 1], 3),
            "max_ms": round(max(latency), 3),
            "cpu_ms_per_sample": round((after["cpu_ms"] - before["cpu_ms"]) / samples, 3),
            "rss_first_kib": rss[0], "rss_last_kib": rss[-1],
            "rss_min_kib": min(rss), "rss_max_kib": max(rss),
            "vm_hwm_last_kib": after["peak_rss_kib"],
            "rss_first_quarter_median_kib": statistics.median(rss[:max(1, samples // 4)]),
            "rss_last_quarter_median_kib": statistics.median(rss[-max(1, samples // 4):]),
            "fds_first": fds[0], "fds_last": fds[-1], "fds_max": max(fds),
            "wire_bytes_min": min(sizes), "wire_bytes_max": max(sizes),
            "observed_rows_min": min(rows), "observed_rows_max": max(rows),
            "limited_samples": limited, "idle_cpu_ms": idle_cpu_ms,
        }
    finally:
        collector.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ruby", type=Path, default=ROOT / "backend/ruby/build/outbound-engine")
    parser.add_argument("--rust", type=Path, default=ROOT / "backend/target/release/outbound-engine")
    parser.add_argument("--reference-ruby", type=Path, help="Optional previous Ruby binary for same-load comparison")
    parser.add_argument("--pairs", type=int, nargs="+", default=[0, 32, 256])
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--idle-seconds", type=float, default=1)
    args = parser.parse_args()
    if (not 5 <= args.samples <= 1000 or not 0 <= args.warmup <= 100
            or not .1 <= args.idle_seconds <= 10
            or any(n < 0 or n > 1024 or n % 2 for n in args.pairs)):
        parser.error("Use 5–1000 samples, 0–100 warmups, 0.1–10 idle seconds, and even pair counts in 0–1024")
    fd_limit = resource.getrlimit(resource.RLIMIT_NOFILE)[0]
    if fd_limit != resource.RLIM_INFINITY and 2 * max(args.pairs) + 32 > fd_limit:
        parser.error("The requested socket count exceeds the process fd limit")
    binaries = {"ruby": args.ruby.resolve(), "rust": args.rust.resolve()}
    if args.reference_ruby:
        binaries["ruby_before"] = args.reference_ruby.resolve()
    report = {
        "architecture": platform.machine(), "kernel": platform.release(),
        "samples": args.samples, "warmup": args.warmup, "idle_seconds": args.idle_seconds,
        "database": "missing", "ui_rendering": False,
        "cpu_tick_ms": 1000 / os.sysconf("SC_CLK_TCK"),
        "sha256": {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in binaries.items()},
        "scenarios": [],
    }
    for index, pairs in enumerate(args.pairs):
        with controlled_sockets(pairs) as endpoints:
            scenario = {"controlled_pairs": pairs, "controlled_rows": len(endpoints)}
            # Alternate execution order to avoid always measuring Ruby first.
            order = list(binaries)
            if index % 2:
                order.reverse()
            for label in order:
                print(f"Measuring {label}: {pairs} local pairs", file=sys.stderr, flush=True)
                scenario[label] = measure(binaries[label], endpoints, args.samples, args.warmup, args.idle_seconds)
            report["scenarios"].append(scenario)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
