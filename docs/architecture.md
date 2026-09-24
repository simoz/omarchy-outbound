# Architecture and shell contract

Phase 0 decision record, 2026-09-24. These are implementation contracts, not
claims that the plugin already exists. See [feasibility](feasibility.md) for
observed results and untested cases.

## Supported development baseline

Target **Omarchy Quattro**, using the official source contract at commit
[`28ceaae70ebac3a0edcc21f2faa77a90dc6d404c`](https://github.com/omacom/omarchy/blob/28ceaae70ebac3a0edcc21f2faa77a90dc6d404c/docs/omarchy-shell.md),
with the trusted built-in bar. The local baseline is Quickshell 0.3.1 and Qt
6.11.2. Do not advertise compatibility with Omarchy 3, arbitrary 4.x versions,
or replacement bars. The latter deliberately do not expose a widget's service
through their entry facade.

The local runtime package is `try-omarchy-runtime 4.0.3-1`, while its Omarchy
`version` file says `4.0.0.alpha`. Its shell source differs from upstream.
Record both identifiers instead of treating the package number as proof of an
upstream release. Phase 1 must validate on this baseline; release compatibility
must name the actual tested Omarchy release and architectures.

Sources: official [plugin guide](https://plugins.omarchy.org/develop.html),
the pinned shell documentation, and the installed `shell.qml`,
`services/PluginShellApi.qml`, `Ui/PluginBarApi.qml`, `Ui/BarWidget.qml`,
`Ui/Panel.qml`, `Commons/Color.qml`, and `Commons/Style.qml`.

## Host integration

- Use plugin ID `io.github.simoz.outbound`, manifest `schemaVersion: 1`, kinds
  `service` and `bar-widget`, and entry points `Service.qml` and `BarWidget.qml`.
  `Panel.qml` is loaded internally by the bar widget, not a separate panel kind.
  Set `barWidget.allowMultiple: false` and `defaultSection: right`.
- Entry points are QML `Item`s. Extend `qs.Ui.BarWidget`: the host injects `bar`,
  `moduleName`, and inline `settings`. A bar surface exists per monitor even
  when duplicate placement is disabled.
- Look up the shared service through `bar.shell.serviceFor(moduleName)` and
  pass it explicitly to child components. Handle initial service absence.
  Do not create a backend per widget or import a relative-path QML singleton.
- The service declares the injected `shell` and `manifest` properties. Start
  only after injection and registered demand, not in `Component.onCompleted`.
  Service creation precedes property injection in the inspected host source.
- Forward `open`, `close`, `toggle`, `closeForPopoutSwitch`, `opened`, and
  `popoutSwitchClosing` from the entry point to its internal panel, as in the
  official guide. Pass `bar`, `settings`, and the anchor item explicitly.
  Use the existing `qs.Ui` popup/keyboard components for placement and focus.
- Bind colors to `qs.Commons.Color` (`bar`, `popups`, palette roles), geometry
  and typography to `Style`, and bar presentation to its injected facade.
  Do not copy a theme at startup or watch theme files independently.
- Persist non-secret plugin settings through the own-plugin scoped
  `shell.updateEntryInline(moduleName, settings)` contract. Rendering and
  input components must not perform collection, DNS, or downloads.

No root manifest is added in Phase 0: declaring entry points before they exist
would create an invalid installable package. No undocumented `activation`
field or automatic installation hook is assumed.

## Ownership and lifecycle

`Service.qml` owns one `Quickshell.Io.Process`, the current immutable snapshot,
filters shared across views, and a registry of live bar/panel consumers.
`BarWidget.qml` owns its monitor-specific anchor; `Panel.qml` owns focus and
presentation. `ui/Globe.qml` only projects local geometry and supplied data.

Use the default `keepLoaded: false` (omit the key): the inspected shell destroys
ordinary services on plugin rescan and on disable/remove. With `keepLoaded:
true`, old service code survives reload until a shell restart; that is not the
desired development lifecycle.

Register/unregister views by stable tokens, including destruction. Derive demand
from all monitors, not from the last panel event. Proposed collection cadence:
2 seconds while any panel is open, 10 seconds for bar-only demand, stopped when
no views remain or the user pauses. These are initial tunables, not measured
performance budgets. No rendering timer runs for a hidden globe. Moving a
scene between compact and expanded surfaces preserves its state and consumer
token rather than transiently stopping collection.

Launch the absolute helper path with an argument list. Keep stdin open for
versioned commands; EOF tells the helper to exit. It must not daemonize or
spawn detached workers. Shutdown cancels pending samples and restart timers,
closes stdin, then terminates the child if necessary. Use a generation token
for callbacks and snapshot acceptance; wait for the previous process to exit
before replacing it. Missing executables and protocol incompatibility are
visible errors, not endless retry loops. Unexpected exits retry after 1, 2,
4, 8, and 16 seconds, then require a user retry; successful validated sampling
resets the budget. Disable/remove/destruction cancels the entire retry chain.

The installed Process API has `stdinEnabled`, `write`, `signal`, and `exited`.
The [Process documentation](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/Process/)
does not substitute for lifecycle tests: EOF, shell crash, hot reload, and
two-monitor transitions remain mandatory Phase 3 checks.

## Collector

Rust is the runtime backend. Use `NETLINK_SOCK_DIAG` TCP dumps for IPv4 and
IPv6; validate multipart lengths, sequence, errors, truncation and interrupted
dumps. An interrupted dump is not a valid empty snapshot. Do not add `ss`
parsing as a silent production fallback; `ss` is a development reference.

Join socket inodes to readable `/proc/<pid>/fd` symlinks and read `comm` for
display names. Read process start time to guard against PID reuse; never read
cmdline or environment. Socket ownership may include several processes or be
unavailable. Preserve all bounded observed owners rather than arbitrarily
claiming one application; count a socket once in totals. Process-level counts
can overlap and must not be summed into the global total.

Identify a socket by the diagnostic cookie and address family within a backend
session; if the kernel provides no usable cookie, use a session-scoped ID
derived from the observed tuple/inode and retire it when absent. Do not claim
identity continuity across unobserved close/reopen races or backend restarts.

V1 displays connected TCP sockets and TCP state, excluding listeners from
connection totals. Both local ends of a loopback connection are separate
observed sockets. The label is an observed socket count, not a count of unique
remote services or users. Include non-Internet addresses as a separate filter
category rather than geolocating them.

**Direction is `unknown` in v1.** Ports, public IPs, and an established state
are not evidence of the initiator. Do not draw directional arrowheads or label
all rows outbound. A future classifier must specify its evidence and handle
missed handshakes and simultaneous open before changing this contract.

Visibility is limited to the accessible network namespace and `/proc` mount.
Keep inaccessible/racing owners as unknown. A socket UID does not grant access
to its process metadata. VPNs and proxies expose locally observed endpoints;
do not infer their upstream destinations. Container namespaces are not entered.

## Protocol and bounds

Plan protocol version 1: UTF-8 JSON objects separated by newlines over private
stdin/stdout. Use complete snapshots initially, no HTTP server and no deltas.
Every snapshot carries `version`, backend `session`, increasing `sequence`,
`observedAtMs` (Unix milliseconds), collector status, coverage, database status,
connections and aggregates. Use a monotonic clock internally for sampling.
Commands carry a request ID and version; reject incompatible versions.

Connection fields: session-local ID, family, local/remote address and port,
TCP state, optional process owners with PID/start time/name, address scope,
direction, and optional country. Country display coordinates belong to the
country marker dataset, not to an asserted exact IP location.

Initial hard limits to implement and test: 2 MiB per JSON line, 4,096 sockets,
16 owners per socket, 128 Unicode characters per display name, 4 KiB per
command, and bounded depth (8). Coordinates must be finite and within latitude
[-90, 90], longitude [-180, 180]; ports are integers in [0, 65535]. Validate
all types and counts on both sides. Truncation is explicit; aggregates describe
the emitted rows, with omitted-row counts reported separately. Coverage must
distinguish denied process access, races, timeout, and unavailable families.
Missing GeoIP must not discard connection rows.

**Integration constraint:** the installed `SplitParser` exposes a delimiter,
but no buffer-size ceiling. Checking a completed line in QML does not bound
memory before its newline. Enforce producer limits in Rust and gate release
on a bounded framing solution and oversized/unterminated-output tests in
Phase 3/4. Do not claim a hostile or corrupted backend is sandboxed by
`SplitParser`. A framing adapter or host support may be needed; no nonexistent
chunk-reader QML API is assumed here.

## Rendering and dependencies

Use orthographic projection, local simplified geometry, country markers and
endpoint arcs. Start with event-driven redraws only. Phase 1 must compare Qt
Quick Shapes with a Canvas prototype at the same dimensions/geometry and
measure drag responsiveness and idle cost. Qt documents the texture-upload
cost of frequent large [Canvas](https://doc.qt.io/qt-6/qml-qtquick-canvas.html)
updates. No continuous full-canvas animation or Qt Quick 3D dependency is
approved by this feasibility result.

Expected direct Rust dependencies: `libc` for Linux interfaces, `serde` and
`serde_json` for the protocol, and `maxminddb` for the local MMDB reader. Prefer
the standard library for scheduling, threads, and file access; no HTTP client,
async framework, packet capture, or Python runtime dependency is required.
Pin exact versions and record transitive licenses in Cargo.lock in Phase 2.
The reviewed `maxminddb` 0.32.0 declares ISC and offers a read-file mode without
the optional mmap/unsafe decoding features; keep those features disabled.
See its [manifest](https://github.com/oschwald/maxminddb-rust/blob/main/Cargo.toml).
