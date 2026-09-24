# ARM64 backend resource measurements

Recorded 2026-09-24 on Linux aarch64, kernel `7.2.5-1-aarch64-ARCH`, with
GCC 16.1.1 and the pinned Spinel/libmaxminddb toolchain from
[the development guide](development.md#build-the-rubyspinel-collector).
[Aggregate measurements and binary hashes](benchmarks/arm64-2026-09-24.json)
contain no observed IPs, names or raw snapshots.

## Workload and interpretation

`tools/benchmark_backends.py` holds IPv4/IPv6 loopback connections open while
measuring each backend sequentially. Each connection produces two observed
socket rows. It checks both endpoints and their ownership on every sample,
rejects failed family dumps, and validates the final frame with the actual UI
protocol. No payloads or external requests are sent. Test sockets use abortive
close to avoid leaving TIME_WAIT rows that inflate subsequent scenarios.

Each short scenario uses one first request, five warmups, 30 measured requests
and a one-second idle interval. The longer run uses 500 measured requests and
ten idle seconds. Requests are back to back, not paced like the UI. The harness
alternates engine order across short scenarios; it is not a randomized trial.
Other sockets in the current namespace remain visible, so observed totals can
vary slightly. The controlled rows must always be present.

Latency covers sending the command through receiving its complete newline,
excluding JSON parsing and assertions in the harness. First-request timing starts
after spawning the process. CPU is the child's user+system tick count, with
10 ms resolution here. RSS and VmHWM are approximate `/proc` measurements; RSS
is sampled after replies and does not capture every transient allocation.
No GeoIP database is loaded and QML rendering is not measured.

## Same-load comparison

The previous Ruby binary was rebuilt from commit `9a5af1e` with the same pinned
toolchain. All three implementations ran against the same held socket set in
each scenario. Values below are median latency and maximum sampled RSS:

| Controlled connections | Previous Ruby | Optimized Ruby | Rust reference |
| --- | --- | --- | --- |
| 0 | 4.53 ms / 3.25 MiB | 4.57 ms / 3.29 MiB | 3.15 ms / 2.63 MiB |
| 32 (64 rows) | 5.31 ms / 4.06 MiB | 5.19 ms / 3.88 MiB | 2.87 ms / 2.46 MiB |
| 256 (512 rows) | 11.40 ms / 11.48 MiB | 10.12 ms / 10.27 MiB | 5.01 ms / 2.94 MiB |

The largest short scenario contained 517 total rows for all three engines.
Ruby's median fell about 11% there. Small-load differences are too small to
claim a general speedup; RSS maxima vary with allocation/GC timing. Rust still
uses less CPU and memory. This does not establish performance parity.

The optimization reuses JSON that is already ASCII instead of allocating a
codepoint array and temporary strings for every character. The existing Unicode
escape path remains in place. Regression checks cover accented/BMP/astral text,
quotes, backslashes and the 2 MiB output limit with recomputed aggregates.

## Longer run and idle behavior

With 256 controlled connections and 500 measured requests:

| Metric | Ruby/Spinel | Rust |
| --- | --- | --- |
| Median / p95 / maximum latency | 9.54 / 10.65 / 11.67 ms | 5.12 / 5.77 / 6.31 ms |
| CPU per snapshot | 9.36 ms | 4.94 ms |
| First / last quarter median RSS | 12.33 / 12.36 MiB | 2.94 / 2.96 MiB |
| Maximum sampled RSS | 12.61 MiB | 2.96 MiB |
| First / last / maximum open descriptors | 4 / 4 / 4 | 3 / 3 / 3 |
| CPU during ten seconds without requests | 0 ms observed | 0 ms observed |

Ruby's first RSS sample was 8.37 MiB and its last was 12.36 MiB: allocation pools
warm up, so first/last alone would overstate steady growth. Quarter medians and
constant descriptor counts show no continuing growth in this finite run. This
is not a proof against leaks over hours. All controlled rows survived; neither
backend reported truncation, scan timeout or scan limits, and neither emitted
unsolicited output. Ownership elsewhere can still be partial.

An earlier diagnostic measured 50 ms of idle CPU over ten seconds in the Ruby
backend. Inspection of the pinned runtime found a 1 ms readiness-poll loop in
its cooperative stdin reader (`lib/sp_io.c`, `sp_io_park_fd_readable`). The
collector now uses a fixed-buffer blocking reader, preserving the 4,096-byte
command limit and Ruby schema validation. Hex encoding across the C string FFI
preserves embedded NUL so invalid bytes cannot be silently truncated. Tests
cover split input, binary input, EOF, oversized input without EOF and termination
while waiting for a partial command. The final idle result means less than one
CPU tick was measured, not a universal guarantee of exactly zero CPU.

## Reproduce and limits

Build both backends as described in [development.md](development.md), then run:

```bash
python3 -B tools/benchmark_backends.py
python3 -B tools/benchmark_backends.py --pairs 256 --samples 500 --idle-seconds 10
# Optional existing previous Ruby binary, measured on the same held sockets:
python3 -B tools/benchmark_backends.py --reference-ruby /path/to/previous-engine
```

The tool requires normal loopback/netlink access; the command sandbox denies
socket creation and is unsuitable for this measurement. It changes no desktop
settings, installs nothing, and saves only aggregate metrics if stdout is
redirected to a file. Run it without concurrent builds or other benchmarks.

These measurements cover one ARM64 system, controlled local load and missing
GeoIP. They do not validate x86_64, loaded GeoIP lookup cost, sustained real-world
traffic, physical multi-monitor behavior, or UI CPU/RAM. No release resource
budget or universal performance guarantee is inferred from these runs.
