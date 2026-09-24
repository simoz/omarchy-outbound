#!/usr/bin/env python3
"""Development-only Linux feasibility probe; opens loopback sockets, no payloads."""

import json
import os
import platform
import socket
import struct
import subprocess
from contextlib import ExitStack
from pathlib import Path


def snapshot(family):
    """Request TCP inet_diag messages using the Linux UAPI, without extensions."""
    # inet_diag_req_v2: family, protocol, ext, pad, states, zeroed sockid.
    request = struct.pack("=BBBBI", family, socket.IPPROTO_TCP, 0, 0, 0xFFF)
    request += bytes(40) + struct.pack("=II", 0xFFFFFFFF, 0xFFFFFFFF)
    header = struct.pack("=IHHII", 16 + len(request), 20, 0x301, 1, 0)
    rows = []
    with socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, 4) as channel:
        channel.settimeout(3)
        channel.bind((0, 0))
        channel.sendto(header + request, (0, 0))
        for _ in range(4096):
            data, _, flags, sender = channel.recvmsg(1024 * 1024)
            if flags & socket.MSG_TRUNC or sender[0] != 0:
                raise RuntimeError("Truncated or non-kernel netlink response")
            offset = 0
            while offset < len(data):
                length, kind, msg_flags, seq, _ = struct.unpack_from("=IHHII", data, offset)
                if length < 16 or offset + length > len(data) or seq != 1:
                    raise RuntimeError("Invalid netlink message")
                body = data[offset + 16 : offset + length]
                if msg_flags & 0x10:
                    raise RuntimeError("Interrupted netlink dump; rerun probe")
                if kind == 2:
                    error = struct.unpack_from("=i", body)[0]
                    if error:
                        raise OSError(-error, os.strerror(-error))
                elif kind == 3:
                    if body and struct.unpack_from("=i", body)[0]:
                        raise RuntimeError("Netlink dump failed")
                    return rows
                elif kind == 20:
                    if len(body) < 72 or body[0] != family:
                        raise RuntimeError("Invalid inet_diag message")
                    source, destination = struct.unpack_from("!HH", body, 4)
                    uid, inode = struct.unpack_from("=II", body, 64)
                    rows.append((source, destination, body[1], uid, inode))
                offset += (length + 3) & ~3
    raise RuntimeError("Netlink dump exceeded the probe limit")


def probe_family(family, address):
    with ExitStack() as stack:
        listener = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
        listener.settimeout(3)
        listener.bind((address, 0))
        listener.listen(1)
        client = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
        client.settimeout(3)
        client.connect(listener.getsockname())
        accepted, _ = listener.accept()
        stack.enter_context(accepted)
        server_port = listener.getsockname()[1]
        client_port = client.getsockname()[1]
        expected = {(client_port, server_port), (server_port, client_port)}
        own_inodes = {
            int(os.readlink(f"/proc/self/fd/{s.fileno()}")[8:-1])
            for s in (client, accepted)
        }
        matches = [
            row
            for row in snapshot(family)
            if row[:2] in expected and row[2] == 1 and row[4] in own_inodes
        ]
        if len(matches) != 2 or any(row[3] != os.getuid() for row in matches):
            raise RuntimeError("Controlled connection missing or incorrect UID/inode")
        reference = subprocess.run(
            [
                "ss", "-H", "-n", "-t", "-p",
                "-4" if family == socket.AF_INET else "-6",
                "state", "established",
                f"( sport = :{server_port} or dport = :{server_port} )",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        lines = reference.stdout.splitlines()
        if len(lines) != 2 or any(
            f"pid={os.getpid()}," not in line for line in lines
        ):
            raise RuntimeError("ss did not confirm both controlled process endpoints")
        comm = Path("/proc/self/comm").read_text().strip()
        if not comm:
            raise RuntimeError("Own process name unavailable")
        # Verify a connection fully between snapshots is absent from the next one.
        short = stack.enter_context(socket.socket(family, socket.SOCK_STREAM))
        short.settimeout(3)
        short.connect(listener.getsockname())
        short_peer, _ = listener.accept()
        stack.enter_context(short_peer)
        short_inodes = {
            int(os.readlink(f"/proc/self/fd/{s.fileno()}")[8:-1])
            for s in (short, short_peer)
        }
        short.close()
        short_peer.close()
        if any(row[4] in short_inodes for row in snapshot(family)):
            raise RuntimeError("Closed socket inode still present")
        return {
            "established_endpoints": len(matches),
            "uid_inode_match": True,
            "own_process_name_readable": True,
            "ss_process_match": True,
            "between_snapshot_connection_missed": True,
        }


def main():
    if platform.system() != "Linux" or os.geteuid() == 0:
        raise SystemExit("Run on Linux as a normal user, without sudo")
    status = dict(
        line.split(":", 1)
        for line in Path("/proc/self/status").read_text().splitlines()
    )
    if int(status["CapEff"].strip(), 16):
        raise SystemExit("Run without effective capabilities")
    result = {
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "uid": os.getuid(),
        "effective_capabilities": 0,
    }
    result["ipv4"] = probe_family(socket.AF_INET, "127.0.0.1")
    result["ipv6"] = probe_family(socket.AF_INET6, "::1")
    try:
        list(Path("/proc/1/fd").iterdir())
        result["pid1_fd_access"] = "readable"
    except PermissionError:
        result["pid1_fd_access"] = "permission_denied"
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
