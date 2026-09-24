# Phase 3 integration validation

Recorded on 2026-09-24: ARM64 Linux, installed Omarchy Quattro runtime
`try-omarchy-runtime 4.0.3-1`, Quickshell 0.3.1, Qt 6.11.2.

## Automated checks

- Node model/protocol tests: passed. Covers shared owners, external process
  names, strict schemas, session/sequence/request matching, aggregate agreement,
  Unicode escapes split at every boundary, framing limits and nesting limits.
- QtTest with the simulated Commons host: passed. Covers filtering, view demand,
  pause retention, configuration validation, keyboard navigation, theme contrast
  and origin-dependent globe arcs.
- QML lint against installed Omarchy imports and plugin manifest validation:
  passed. The upstream missing `QProcess::ExitStatus` qmltypes enum is locally
  suppressed for the no-argument exit handler.
- Rust ordinary tests, Clippy and formatting: passed. Snapshot serialization
  remains within 2 MiB after ASCII escaping and round-trips Unicode names.
- `python3 -B tests/check_transport.py`: all nine modes passed using actual
  Quickshell processes: normal, missing, malformed, incompatible, oversized,
  retry, late, native and crash. Local fixture helpers exercise cancellation,
  restart backoff and pipe failures; native mode uses the release Rust binary.
  Killing the test shell also terminates its helper.

## Real Omarchy host

A temporary plugin copy and controlled loopback socket were used. The test
observed that socket through the real service, then checked selection, search
and camera retention across panel/window expansion, collapse, hide and reopen.
The scene and collector PID stayed unchanged through those transitions. Hidden
panels retained the bar's 10-second cadence. Pause terminated the collector;
resume created a new session. Plugin rescan and disable terminated old helpers.
The temporary plugin was disabled and removed after the test.

The host cached previously loaded QML at an earlier temporary plugin URL.
This run therefore used a fresh temporary plugin ID; it does not establish
that rescanning replaces code already cached at the same URL. Rescan lifecycle
cleanup was tested with unchanged code at the fresh URL.

## Visual checks and limits

Settings were rendered and inspected offscreen with dark colors at 1440×940
and light colors at 760×640. The smaller popup scrolls; keyboard focus scrolls
controls into view. These captures use simulated data and a simulated host,
not observed personal traffic. Live host behavior was checked separately above.

Physical multi-monitor behavior, x86_64, release packaging/glibc compatibility,
and Phase 4 CPU/memory performance budgets remain unverified. Multiple view
registration is covered in service and transport tests. No provider database
was downloaded; local MMDB behavior is covered by backend fixtures. Without a
database, connection rows remain visible with unknown public countries; without
a manual origin, no origin arcs are drawn. Qt allocates incoming chunks before
JavaScript bounds its accumulator; arbitrary configured executables are not
sandboxed by this transport.
