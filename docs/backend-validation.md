# Phase 2 backend validation

Recorded 2026-09-24 on Linux ARM64, Rust/Cargo 1.98.1 and the host described in
[feasibility.md](feasibility.md). These results cover the standalone collector;
they do not certify real-data QML integration, x86_64 or release packaging.

## Implemented

- Unprivileged TCP IPv4/IPv6 socket diagnostics, multipart validation and
  per-family failure reporting; no `ss` production fallback.
- Bounded proc ownership scans, multiple owners, process start-time identity
  checks, explicit denied/racing/limited observations and no cmdline/environment.
- Session IDs, diagnostic-cookie identity, retirement of fallback identities,
  conservative address classification and unknown connection direction.
- Local country MMDB reading with structural validation, bounded cache, build
  age reporting and explicit missing/invalid/unreadable states. No database or
  downloader is bundled, and no public lookup service is used.
- Request-driven JSON-line protocol, bounded commands, full snapshots, coherent
  emitted-row aggregates, byte/row limits, shutdown and stdin-EOF handling.

## Recorded checks

| Check | Result |
| --- | --- |
| `cargo test --locked --offline` | 14 ordinary tests passed; two native tests explicitly excluded from this invocation |
| Native `--test linux -- --ignored` | Two tests passed: controlled IPv4/IPv6 sockets versus `ss`, and executable request/response/EOF |
| `cargo clippy --all-targets --locked --offline -- -D warnings` | Passed |
| `cargo fmt --check` | Passed |
| `cargo build --release --locked --offline` | Passed on ARM64 |
| `git diff --check` | Passed |

Cargo commands use `--manifest-path backend/Cargo.toml` from the repository
root. The initial dependency fetch used the network; tests and subsequent
builds were offline. The dependency graph is pinned and its declared license
inventory is in [backend/DEPENDENCIES.md](../backend/DEPENDENCIES.md).

The native socket test runs as an ordinary user with zero effective
capabilities. It creates connected loopback pairs for both families, checks
both established endpoints, current UID and owning PID, compares with `ss`,
and checks stable identities on a subsequent sample. A short connection closed
between samples is not recorded as an established historical connection.
No remote endpoint is contacted. Test reports do not dump unrelated host
connections. The executable test checks echoed request IDs, increasing
sequences, stable session ID, row totals and EOF exit after two snapshots.

Parser tests cover multipart completion, short/invalid messages, sequence and
family mismatch, interrupted dumps, permission errors, listener exclusion,
row limits and bounded arbitrary byte inputs. Proc fixtures cover duplicate
fds, shared sockets, the owner limit, inaccessible directories, disappearing
process entries and an expired scan deadline. Unit tests cover stat names with
spaces/parentheses and rejection of differing before/after process start times.
They do not force a real kernel PID-reuse race.

GeoIP fixtures are tiny synthetic MMDBs generated in tests, with fictional
country assignments. They exercise the actual reader, IPv4 and IPv6 lookup,
mapped-address normalization, exclusion of special addresses, build age,
invalid codes, corruption, excessive file size and permissions. These are not
DB-IP accuracy or provider compatibility certification with a production file.
Protocol tests cover idle EOF, explicit shutdown, unsupported versions and
oversized unterminated input without waiting for EOF. Large synthetic snapshots
exercise the 2 MiB limit and recomputation of counts after truncation.

## Remaining boundaries

Phase 3 must connect the service and collector, provide visible coverage/GeoIP
states and attribution, and verify restart/disable/reload/multi-monitor demand.
The current QML preview remains simulated. A blocking stdout consumer requires
host lifecycle management; do not infer responsive cancellation from an idle
EOF test. Producer limits do not establish a bound on corrupted helper output
inside Quickshell's SplitParser.

Phase 4 still needs CPU/RAM measurements with real large socket sets, target
resource budgets, output backpressure and host-crash tests. No x86_64 runtime,
VPN/container namespace certification, real GeoIP-provider file, 1.85 MSRV or
glibc 2.39 baseline was tested. Snapshot/proc ownership is inherently non-atomic;
short sockets, invisible processes and undetectable close/reuse races remain
limitations. The collector does not persist socket history.
