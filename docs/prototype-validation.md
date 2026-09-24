# Phase 1 prototype validation

Recorded 2026-09-24 on the ARM64 environment listed in
[feasibility.md](feasibility.md). The implementation is a simulated-data UI;
this record does not validate a live network collector.

## Implemented

- Namespaced service plus bar-widget manifest; shared simulated state across
  bar instances. Counts are labelled DEMO even before opening a view.
- Orthographic, rotatable local Natural Earth globe, grid, illustrative arcs,
  country callouts and coordinated country filters. Unknown/local rows are
  retained without plotted coordinates. No directional arrows.
- Search and application/address-family filters, virtualized connection list,
  selected application/PID/IP details and explicit Copy IP action.
- Popup and expanded window share one scene. Closing/reopening also preserves
  camera, filters and selection. Small layouts stack into one scrollable column.
- Immediate theme bindings, keyboard controls, reduced motion initially on,
  optional scanlines and sample/empty/error/busy scenarios (240 rows, long names).
- No backend, network operations or automatic clipboard changes.

## Verification results

| Check | Result and boundary |
| --- | --- |
| Node model/projection tests | Passed: combined filters, unknown/local rows, scenario totals, limb clipping and finite rotated geometry |
| QtTest | 10 passes including setup/cleanup: service transitions, keyboard search/Escape, virtualized-list navigation, globe navigation, reduced motion/hidden state, theme reactivity and copy signal |
| QML lint | Passed without warnings with the real shell `qs` import prefix |
| Omarchy manifest validator | Passed |
| Visual preview | Inspected dark and light at 1100 px, busy at 420 px; real Omarchy theme modules, simulated host |
| Real shell loading | Passed on the running Omarchy/Hyprland desktop with the built-in top bar |
| Live panel → window → panel | Same scene identity retained, with query `Browser`, selected `demo-0` and longitude 33 preserved |
| Live hide → summon | Filter and camera remained unchanged |
| Temporary installation cleanup | Test plugin disabled and removed; not left installed |

The live test used a temporary copy of the runtime files with an additional
test-only IPC handler to inspect scene identity and invoke transitions. No test
handler is shipped in the plugin. The expanded scene was captured directly,
without capturing the rest of the desktop. The clipboard assertion used the
UI signal in QtTest, without replacing the user's clipboard.

## Renderer experiment

Both paths use the same projected outline/grid/arc vertices. Natural Earth
contributes 288 exterior rings and 10,642 points. Measured at 1100×1100 in
Quickshell offscreen on this ARM64 environment, requesting 120 rotation ticks
at 16 ms intervals:

| Renderer | Mean timer interval | p95 timer interval | Process CPU time |
| --- | --- | --- | --- |
| Canvas | 16.8 ms | 23 ms | 2.50 s |
| Qt Quick Shapes | 23.9 ms | 41 ms | 3.41 s |

CPU times include process startup and the subsequent idle observation, not
just drawing. Timer intervals measure event-loop responsiveness, not displayed
frames or GPU latency. Offscreen results favor Canvas for this prototype only.
Retain the Shapes path for reproducible comparison on target GPUs. Default
rendering is event-driven Canvas; optional rotation is approximately 30 Hz
and stops when hidden or reduced motion is enabled.

A final Canvas run (17.1 ms mean, 25 ms p95) recorded **zero** additional paints
during a 350 ms idle window after allowing the last rotation frame to settle.

## Remaining checks and limits

No x86_64, multi-monitor, alternate bar-edge, fractional display scaling or
target-GPU performance certification has been performed. Theme switching was
checked through the real theme components in an isolated process; the user's
desktop theme was not changed. The actual desktop smoke test used its current
theme and top bar. Empty/error recovery and copy dispatch were exercised in
automated tests, not with a failing live collector.

There is no persisted settings editor, GeoIP database or Rust process. The
prototype must receive visual review before Phase 2. The earlier approved
mockup was unavailable in the repository; styling follows the written plan.
