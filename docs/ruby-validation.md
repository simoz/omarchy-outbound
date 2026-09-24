# Ruby/Spinel port validation

Recorded 2026-09-24 on Linux ARM64 with GCC 16.1.1, Spinel
`66ae8c07f2d94f86f31fe7902650e796a79895fc`, libmaxminddb 1.12.2
(`cba618d6581b7dbe83478c798d9e58faeaa6b582`), Python 3.14 and the installed
Omarchy/Quickshell tools. The sources and compiler were built locally; no
system package installation or plugin installation was performed.

## Implementation

`backend/ruby/` is the default for `run-ui.sh` and `run-backend.sh`. The UI still
uses protocol v1. The launcher prints the actual executable path and overrides
a saved preview path so an old Rust setting does not silently keep Rust active.
`OUTBOUND_ENGINE=rust` is an explicit reference option. Neither launcher falls
back to Rust when Ruby compilation fails.

Ruby handles bounded commands, process attribution, scope policy, session and
socket identity, GeoIP caching, aggregates and ASCII output. C adapters handle
netlink framing/syscalls and libmaxminddb. Netlink errors discard a whole family;
missing ownership and truncated scans remain visible. Process directory reads
are streamed and identities checked before/after matching fds. Database files
are copied into a sealed anonymous file before mapping, with size, tree, record
and metadata checks. No helper subprocess participates in collection.

The pinned Spinel's `String#codepoints` stops at an embedded NUL; process-name
sanitization therefore uses the length-aware character iterator. Tests include
Unicode, embedded controls, shared fds and an empty `stat` from a disappearing
process. Wire JSON cannot contain raw NUL and uses explicit Unicode escaping.

## Checks

- C adapters compiled with `-Wall -Wextra -Werror`. Native tests cover truncated
  headers/bodies, sequence/family mismatch, interrupted dumps, completion,
  listeners, omission counts and bounded arbitrary input.
- The 11 protocol tests run against a driver importing the production Ruby
  parser. Fatal responses can also be compared with the existing Rust binary.
- Five backend test groups cover controlled IPv4/IPv6 sockets and comparison
  with Rust, standalone database validation, EOF/shutdown/fatal errors, closed stdout, and the
  compiled Ruby unit/fixture suite. Ruby units cover scope boundaries, stable
  and retired fallback IDs, shared-owner aggregation, the 2 MiB ASCII wire
  bound, owner limits, PID reuse, Unicode, corrupt/immutable MMDBs, public-only
  lookup and negative cache accounting. Socket tests validate complete
  snapshots with the actual `Protocol.js` and report only controlled outcomes.
- Real Quickshell processes in an isolated offscreen host passed the transport
  modes: normal, missing executable, malformed, incompatible, oversized,
  retries, late responses, native Ruby and shell crash. Native mode exercises
  repeated sampling, multiple view registrations, pause/reopen/resume and
  teardown. The shell-crash mode uses its existing fixture helper.
- GeoIP UI fixture checks passed success/reload, custom database, failure and
  cancellation with the Ruby validator. No live database was downloaded.
- Node protocol tests, plugin manifest validation, shell syntax and
  `git diff --check` passed.

Loopback/netlink tests require execution outside the restricted command sandbox:
inside it, socket creation is denied. This denial was not treated as successful
collection. The remaining checks use local data and do not need external APIs.

## Limits

These results do not validate the full port on x86_64, physical multiple
monitors, an installed plugin, a distribution glibc baseline, or comparative
resource usage on a busy machine. The earlier Spinel x86_64 feasibility probe
covered only isolated building blocks. The Ruby port has not inherited the
Rust collector's earlier real-host certification.

`ldd` on this binary lists glibc, libm and libcrypt; libmaxminddb is statically
linked. This is not a fully static or universally portable binary. No binary,
compiler checkout or third-party library is committed. Distribution still needs
license/NOTICE packaging and architecture-specific validation.
