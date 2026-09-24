# Development

The repository currently contains Phase 0 documentation and a Linux feasibility
probe. There is no plugin manifest, QML prototype, or Rust backend yet.

## Reproduce the socket experiment

Requirements: Linux, Python 3.11+ standard library, iproute2 (`ss`), enabled IPv4
and IPv6 loopback, and access to NETLINK_SOCK_DIAG and `/proc/self/fd`.

```bash
python3 -B tools/probe_sockets.py
```

Run as a normal user without capabilities or sudo. The probe opens only
loopback connections and sends no application payloads. It samples TCP sockets
but reports only assertions about its controlled connections. It requires both
IPv4 and IPv6 to pass; a disabled family or restricted syscall is a failed
probe, not a successful zero-result test. A denied `/proc/1/fd` is recorded as
an expected visibility limitation, not bypassed. Do not run it on an environment
where local socket creation is forbidden and infer a kernel-wide limitation.

The [recorded ARM64 results](feasibility.md) cover Linux collection only.
Python is a development aid; the runtime collector will be Rust.

## Checks for the current phase

Review Markdown links and decisions against the cited sources, then run:

```bash
git diff --check
```

If Ruff is installed, check the development probe with:

```bash
ruff check tools
ruff format --check tools
```

Do not run `omarchy plugin validate .` before real manifest entry points exist.
There is no backend suite, prepared runtime, or renderer to invoke at this
stage. Commands inherited from a different project's instructions are not
applicable to this repository.

## Later-phase validation

- Phase 1: manifest validation with `omarchy plugin validate .`; QML lint using
  `/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell` on the actual QML files;
  real host loading, all bar edges, multiple monitors, focus/Escape, small
  sizes, theme changes, and Shapes/Canvas profiling. Mark simulated data.
- Phase 2: Rust unit and controlled local integration tests for IPv4/IPv6,
  address scope, owner races, PID reuse, shared fds, malformed netlink, GeoIP
  failure and protocol validation. Test the final Rust collector, not just
  this Python probe.
- Phase 3/4: helper EOF/crash/disable/reload and late callbacks; bounded restart
  behavior, hidden-view idle cost, oversized and unterminated output, no
  accidental external traffic, and explicit partial coverage.
- Phase 5: build against the declared glibc baseline, inspect dependencies and
  required symbols, and run installation/update/removal on x86_64 and ARM64.

Record environment, commands, outcomes and limitations for each check. A Qt
preview with a simulated host is not a real Quickshell/Hyprland integration
test. Do not change the user's desktop or install reference projects merely
to inspect their source.
