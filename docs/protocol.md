# Collector protocol v1

Implemented by `backend/ruby/` (default) and `backend/src/` (Rust reference), Linux only, and consumed by `Collector.qml` through
`Protocol.js`.

## Invocation and framing

`outbound-engine [--database /absolute/path/to/country.mmdb]` runs as the current
user. It performs no downloads, DNS queries, HTTP requests, packet capture,
shell commands or privilege changes. Collection uses a kernel netlink socket;
there is no network listener. Only the development test invokes `ss`.

Stdin/stdout carry UTF-8 JSON objects, one per newline. Snapshot output escapes
non-ASCII characters as JSON Unicode escapes (including surrogate pairs), so
Qt string chunk boundaries cannot corrupt process names. Stdout has no banners or
logs. Stderr errors contain neither process names nor IPs nor input contents.
There is no autonomous sampling: the caller requests a snapshot at its chosen
cadence and must keep draining stdout. EOF exits after any current bounded
sample/write; `shutdown` exits after acknowledging. A closed output pipe exits
cleanly. There is no worker process or detached thread. Host termination and lifecycle checks are recorded in
[integration-validation.md](integration-validation.md).

Commands have exactly these fields:

```json
{"version":1,"requestId":"sample-1","command":"snapshot"}
{"version":1,"requestId":"stop-1","command":"shutdown"}
```

`requestId` is 1–64 ASCII letters, digits, `_` or `-`. Unknown fields, duplicate
fields, wrong types, invalid UTF-8, unknown commands, unsupported versions and
invalid IDs are fatal. Commands including newline cannot exceed 4,096 bytes;
JSON nesting cannot exceed eight containers. The reader bounds input before
allocation of a JSON value, including input without a newline. A partial final
line is rejected, not executed.

Fatal input produces one response and a nonzero exit:

```json
{"version":1,"kind":"error","requestId":null,"code":"unsupportedVersion","fatal":true}
```

Other codes: `invalidCommand`, `invalidRequestId`, `commandTooLarge`,
`commandTooDeep`, `unterminatedCommand`. Invalid requests are not reflected.
Shutdown acknowledges `{"version":1,"kind":"stopped","requestId":"stop-1"}`.

## Database validation command

`outbound-engine --check-database --database /absolute/path/to/country.mmdb`
performs bounded local validation without opening socket diagnostics or reading
stdin. It requires a verified country database with IPv6 support (covering both
address families), and emits its database status as one JSON line. Invalid or
unreadable files return a nonzero exit. The installer uses this separate mode;
the snapshot protocol remains version 1.

## Snapshot fields

| Field | Meaning |
| --- | --- |
| `version`, `kind`, `requestId` | `1`, `snapshot`, echoed validated request ID |
| `session` | Random 128-bit hex ID, newly generated per backend process |
| `sequence` | Increasing integer starting at 1 |
| `observedAtMs` | Unix milliseconds at completion of collection; not an atomic kernel timestamp |
| `status` | `ok`, `partial`, or `error` when both family dumps fail |
| `coverage` | Family/ownership results and truncation; see below |
| `database` | Independent local GeoIP availability/age/error status |
| `connections` | Up to 4,096 observed connected TCP sockets |
| `aggregates` | Counts computed from exactly the emitted connections |

Each connection contains `id`, `family` (`IPv4`/`IPv6`), `local` and `remote`
objects with `address` and integer `port`, TCP `state`, socket `uid`, `owners`,
remote-address `scope`, `direction` (always `unknown`), and nullable `country`.
Addresses retain their observed family, including IPv4-mapped IPv6; scope and
GeoIP normalize only the mapped address. Listening and closed/unconnected
sockets are excluded. Both ends of a loopback connection count separately.

Owners contain `pid`, `startTimeTicks` as a decimal string (kernel clock ticks
since boot, not a timestamp), and `name` from `comm`. PID/start time are checked
before/after each matching process scan; a reused PID is not an identity match.
Names are plain text, stripped of controls and limited to 128 Unicode scalars.
There are at most 16 distinct owners per socket, with duplicate fds collapsed.
No process arguments or environment are inspected. Associations remain
best-effort: the netlink dump and proc scan are not atomic; invisible ownership
and undetectable close/reuse races cannot be ruled out.

Cookie-based IDs combine session, observed family and the kernel diagnostic
cookie. If both cookie words are `INET_DIAG_NOCOOKIE`, a tuple/inode-based key
gets a session-local counter ID retained only across consecutive observed
snapshots. Absence, collection failure or truncation retires fallback identity.
No cross-session continuity or missed-connection history is claimed.

`aggregates.sockets` counts rows once. `countries` maps codes, `unknown` (public
address without country), and `nonInternet` (special-use address) to counts.
`applications` groups by observed process name; the same name counts at most
once per socket, but different owners' names may overlap, so application counts
must not be summed into a global total. `unknownOwners` counts rows with no
observed owner. These counts describe observations, not unique remote services.

## Coverage and resource bounds

`coverage.ipv4` and `ipv6` are null for a complete family dump, otherwise one of
`denied`, `timeout`, `unavailable`, `interrupted`, `malformed`, `io`. An errored
family contributes no partial rows. Dumps validate sequence, lengths, family,
TCP state, kernel sender, truncation/overrun, multipart completion and interrupted
dump flags. Each family has a one-second deadline and a 4,096-datagram limit.
Datagram buffers are 256 KiB. An unsupported family is explicit, never silently
represented as a successfully empty family.

`coverage.processes` reports `denied`, `races`, `errors` operation counters,
`timedOut`, `scanLimited` and `ownersOmitted`. The proc scan allows 400 ms,
65,536 directory entries and 262,144 fd entries. Small proc files are capped at
4 KiB. These bounds may cause partial ownership on busy hosts; counters do not
represent distinct processes in every case. The available proc mount may hide
processes completely without returning a permission error. `namespace` is
`current`: other network namespaces are never entered.

`coverage.omittedRows` counts known rows excluded by row/byte bounds;
`truncated` marks that condition. Failed families may have additional unknown
rows, so this is not a machine-wide missing-socket count. Output including
newline is at most 2 MiB. If names/shared owners exceed that budget, the emitted
row set is reduced and aggregates recomputed. The consumer uses `SplitParser` with an empty marker to receive raw chunks,
then bounds its own accumulator before JSON parsing. It rejects non-ASCII wire
output, excessive depth, invalid schemas/aggregates and stale request/session/
sequence values. Only one request is outstanding, with a five-second watchdog.
The application accumulator is bounded; Qt allocates each incoming chunk before
JavaScript sees it. This is not a sandbox for arbitrary hostile executables.

Transient exits retry after 1, 2, 4, 8 and 16 seconds. Invalid output or failure to
start requires explicit retry or a path change. Cancellation closes stdin,
ignores late output, and escalates to TERM/KILL after bounded grace periods.
Replacement waits for the previous process to exit.

## GeoIP and address scope

No database is bundled. An explicitly supplied country MMDB is read once,
limited to 64 MiB, structurally verified and cached in memory. Rust uses the
`maxminddb` crate. Ruby uses libmaxminddb against a sealed anonymous copy of the
file; its adapter checks search-tree cycles/depth and decodes referenced records
before exposing the reader. Replacing or truncating the source cannot change
an already loaded database. Database states are `missing`, `unreadable`, `invalid`, `ready`.
`buildEpochSeconds` and derived `releaseMonth` come from database metadata;
`stale` means build age exceeds 90 days. This is a build month, not independently
verified provider-release provenance. `lookupErrors` is a cumulative count of
failed/invalid uncached lookups. Missing or corrupt databases never remove rows.
A valid record supplies `country.iso_code`; two uppercase letters are retained,
including `XK`, while `ZZ` is unknown. No coordinates are inferred. The UI must
handle codes without a known display marker. Cache capacity is 8,192 addresses,
FIFO eviction, including negative lookups. Restart with a new file to reload;
there is no automatic update or implicit provider selection.

The address rules were reviewed against IANA's IPv4 and IPv6 special-purpose
registries, both last updated 2025-10-09, retrieved 2026-09-24:

- [IPv4 registry](https://www.iana.org/assignments/iana-ipv4-special-registry/)
- [IPv6 registry](https://www.iana.org/assignments/iana-ipv6-special-registry/)

Scopes are `public`, `loopback`, `private`, `linkLocal`, `shared`,
`documentation`, `multicast`, `unspecified`, `reserved`. Only `public` is queried.
Specific globally reachable anycast exceptions inside protocol-assignment
blocks are preserved. Product policy conservatively excludes translation and
tunnel ranges (`64:ff9b::/96`, local NAT64, Teredo, 6to4), benchmarking,
unspecified/deprecated/reserved ranges and IPv6 outside current `2000::/3`
global unicast, with ULA/link-local/multicast classified separately. This policy
is stricter than IANA's globally-reachable flag and does not assert routability.
No registry is fetched at runtime. See [data licensing](data-and-distribution.md)
for the planned DB-IP distribution and attribution requirements.
