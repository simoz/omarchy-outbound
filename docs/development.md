# Development

The repository contains a QML prototype with simulated data, Phase 0
documentation, a standalone Rust collector and a Linux socket feasibility probe.
The UI still uses simulated data; backend integration is Phase 3.

## Preview the prototype

On the supported Omarchy installation, assemble an isolated Quickshell config:

```bash
outbound_preview=$(python3 -B tools/prepare_preview.py)
qs -p "$outbound_preview"
```

The helper copies the prototype and installed `Commons`/`Ui` modules to a new
temporary directory. It does not install a plugin or change the desktop bar.
Rebuild the preview after editing source files. This is a simulated host,
although it uses actual Omarchy theme components.
The preview follows the installed Omarchy theme by default. Set
`OUTBOUND_THEME=light` or `OUTBOUND_THEME=dark` only to force a visual-test palette.

To capture only the prototype offscreen:

```bash
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
  OUTBOUND_THEME=light OUTBOUND_CAPTURE=/tmp/outbound-light.png \
  qs -p "$outbound_preview"
```

Optional environment controls: `OUTBOUND_WIDTH`, `OUTBOUND_HEIGHT`,
`OUTBOUND_SCENARIO` (`sample`, `empty`, `error`, `busy`), `OUTBOUND_RENDERER`
(`canvas`, `shapes`), and `OUTBOUND_BENCHMARK=1`. The benchmark rotates the same
geometry for 120 ticks, logs timing and an idle repaint count, then exits.
Measurements from offscreen rendering are not GPU frame-rate guarantees.

The prototype always displays a simulated-data banner. The fixture uses
documentation IP ranges with explicitly fictional country assignments; these
must not become GeoIP expectations for the production collector. No download,
socket collection, DNS lookup or external process is initiated by the plugin.
The surrounding Omarchy theme components retain their usual host behavior.

Open the keyboard guide with F1 or the header’s ? button. Escape closes the
guide and restores focus; arrow keys and Page Up/Down scroll it. Hover tooltips
are omitted; controls retain accessible names.

Tab/Shift+Tab move through controls, Enter/Space activate buttons, and Escape
closes the view. The focused globe accepts arrow keys and Home; search fields
retain those keys for editing. Drag rotates the globe; choose a country in the
list or on the globe to filter. Reduced motion is on initially. Scenarios and
display toggles are session-only prototype state, available from the header
settings button. Selecting a country updates the application breakdown; selecting
an application row filters the connections. The default preview is 1440×940.

## Prototype checks

```bash
node --test tests/*.test.cjs
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
  /usr/lib/qt6/bin/qmltestrunner -input tests -import tests/stubs -o -,txt
omarchy plugin validate .
git diff --check
```

QtTest uses a minimal `qs.Commons` facade because Quickshell's modules are
embedded in its executable and cannot be loaded by plain qmltestrunner. These
tests cover real plugin controls and state with a simulated host. Theme
bindings and panel/window transitions also need the real-host check described
in [prototype-validation.md](prototype-validation.md).

For lint, expose the installed shell under its `qs` import prefix in a temporary
directory; `-I /usr/share/omarchy/shell` alone does not resolve that prefix:

```bash
outbound_imports=$(mktemp -d /tmp/outbound-imports.XXXXXX)
ln -s /usr/share/omarchy/shell "$outbound_imports/qs"
/usr/lib/qt6/bin/qmllint -I "$outbound_imports" \
  BarWidget.qml Panel.qml Service.qml ui/*.qml
```

For a real host check, copy the runtime files (`manifest.json`, root QML/JS,
`ui/`, `assets/`, `fixtures/`) into an unused
`~/.config/omarchy/plugins/io.github.simoz.outbound/`, rescan with
`omarchy-shell shell rescanPlugins`, and enable with
`omarchy plugin enable io.github.simoz.outbound`. This changes the bar and must
be intentional. Do not overwrite an existing plugin. Summon/hide through the
normal shell IPC, and disable the temporary plugin after testing. There is no
backend required to run the simulated UI.

## Build and try the Rust collector

From the repository root, on Linux with Rust/Cargo installed:

```bash
./run-backend.sh
```

The launcher builds the release binary when needed, requests one snapshot and
exits. It also works when invoked by absolute path from another directory.
Arguments are forwarded to the collector, for example:

```bash
./run-backend.sh --database /path/to/country.mmdb
```

The equivalent manual commands are:

```bash
cargo build --manifest-path backend/Cargo.toml --release --locked
printf '%s\n' '{"version":1,"requestId":"sample-1","command":"snapshot"}' | \
  backend/target/release/outbound-engine
```

This prints one real socket snapshot as JSON, then exits on stdin EOF. It does
not install anything or change the QML preview. Ownership is best-effort and
may be partial; direction stays unknown. No country database is downloaded.
To use an existing local country MMDB, append `--database /path/to/country.mmdb`.
Missing GeoIP still yields connection rows. See [protocol.md](protocol.md).

Run tests as a normal user, without extra capabilities:

```bash
cargo test --manifest-path backend/Cargo.toml --locked
cargo clippy --manifest-path backend/Cargo.toml --all-targets --locked -- -D warnings
cargo fmt --manifest-path backend/Cargo.toml --check
```

The ordinary suite uses local proc/MMDB fixtures and child-process protocol
checks. The explicit Linux integration test opens controlled loopback sockets
with IPv4 and IPv6, queries kernel netlink and compares them with `ss`:

```bash
cargo test --manifest-path backend/Cargo.toml --locked --test linux -- --ignored
```

It requires `ss`, permitted netlink access and both loopback families; failure
or an unavailable family is not a successful empty result. Assertions report
only controlled test outcomes, not unrelated socket details. These native
checks have been run on ARM64; x86_64 and the release glibc baseline remain
unverified. See [backend-validation.md](backend-validation.md).

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

## Documentation and Python checks

Review Markdown links and decisions against the cited sources, then run:

```bash
git diff --check
```

If Ruff is installed, check the development probe with:

```bash
ruff check tools
ruff format --check tools
```

No Python package preparation is necessary. The geometry helper accepts only
the pinned local input documented in [the map notice](../assets/NOTICE.md).
The other project's backend test and runtime-preparation commands do not apply.

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
