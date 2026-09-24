# Development

The QML service runs the Ruby/Spinel collector through Quickshell.
The Rust collector remains available for explicit comparison. Python is also used by the explicit GeoIP installer and city search; neither Python nor Node
is a runtime collection dependency.

## Run the live interface

```bash
./run-ui.sh
# Optional existing country database:
OUTBOUND_DATABASE=/absolute/path/to/country.mmdb ./run-ui.sh
```

The launcher builds the Ruby collector when sources change and opens a fresh
isolated preview. It prints the selected executable on stderr and overrides a
saved preview backend path; `OUTBOUND_BACKEND` is still an explicit override.
Use `OUTBOUND_ENGINE=rust ./run-ui.sh` to build and run the Rust reference.
Open settings to change the backend/database paths, sample interval (1–60 s),
manual origin or data source; pause/resume and retry are also available there.
Preview settings last for that session. Installed collection settings are saved
through the host's inline plugin configuration; display toggles are session-only.
The bar alone samples every 10 s; an open panel/window uses the configured interval.
Pausing, switching to simulated data or removing every view stops the process.
No database or origin is fetched automatically. Click **Install GeoIP** on the
globe, or **Install / update managed GeoIP** in settings, to download DB-IP Lite.
The installer requires Python 3.11+, validates the database with the built
collector, and reloads it on success. Closing the last open view cancels a
running download. See [geoip.md](geoip.md) for paths, notices and the CLI.

For an installed plugin, place the built binary at
`${XDG_DATA_HOME:-$HOME/.local/share}/outbound/bin/outbound-engine`, or set its
absolute path in settings. Copy the runtime files as described below.


## Choose the globe origin

Open settings with the gear, or click **Set origin to connect destinations** on
the globe. Under **Origin**, type a city (for example `Genoa, Italy`), press
**Search** or Enter, then choose a result to save the origin immediately.
Coordinates stay editable; use **Apply collection settings** to save manual
edits, or clear both coordinates and apply to remove the origin. The preview
retains collection settings in `${XDG_CONFIG_HOME:-$HOME/.config}/outbound/preview.ini`
across launches. `OUTBOUND_BACKEND` and `OUTBOUND_DATABASE` override saved paths.

Like Vessel, search uses [Photon/OpenStreetMap](https://github.com/komoot/photon).
Only explicit searches contact the provider; typing does not send requests.
The query text is sent, never observed IPs or application names. Results are
limited to six, cached for the session (20 queries), and requests are separated
by at least 1.1 seconds. Closing settings, changing the query or closing the last
view cancels the search and ignores late replies. Saved origins need no lookup.
Python 3 is required for this optional helper. A failed search leaves manual
coordinate entry available. Public service availability is not guaranteed.

Tests: `python3 -B -m unittest discover -s tests -p 'test_search_city.py'` and
`python3 -B tests/check_origin_search.py` (real Quickshell, local fixture helper).
QtTest also covers choosing a city, saving coordinates and focus in the editor.
Run `python3 -B tests/check_preview_settings.py` to verify persistence across
fresh previews with an isolated configuration directory.

## Generate real test connections

With the live UI open, run this in another terminal:

```bash
./test-connections.sh
# Shorter run or explicit targets:
./test-connections.sh --duration 60 --host www.python.org --host www.kernel.org
```

The script opens up to five default HTTPS targets in parallel for two minutes.
It sends HEAD requests, holds connections for up to 20 seconds, and reconnects
at most once every five seconds after a connection ends. Ctrl+C closes test
sockets. Filter the UI by `python3`; every connection belongs to this real test
process. DNS/CDNs determine actual destination IPs and countries, so geographic
spread is not guaranteed. GeoIP and a configured origin are needed for globe
arcs. No fixture IPs or invented countries are injected into the UI.

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

The default preview displays a simulated-data banner. The fixture uses
documentation IP ranges with explicitly fictional country assignments; these
must not become GeoIP expectations for the production collector. In simulated mode, the plugin starts no collector, download or DNS lookup.
Set `OUTBOUND_LIVE=1` to use live data; `OUTBOUND_BACKEND` can override the binary.
The surrounding Omarchy theme components retain their usual host behavior.

Open the keyboard guide with F1 or the header’s ? button. Escape closes the
guide and restores focus; arrow keys and Page Up/Down scroll it. Hover tooltips
are omitted; controls retain accessible names.

Tab/Shift+Tab move through controls, Enter/Space activate buttons, and Escape
closes the view. The focused globe accepts arrow keys and Home; search fields
retain those keys for editing. Drag rotates the globe; choose a country in the
list or on the globe to filter. Connection arcs pulse by default; Reduced motion keeps them static. The pulse
animates a cached vector overlay without repainting the globe Canvas, and stops
when the view is hidden or collection is paused. Live arcs require a manual
origin; use **Set origin to connect destinations** on the globe to open settings.
No directional packet flow is inferred. Scenarios and
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
  BarWidget.qml Panel.qml Service.qml Collector.qml ui/*.qml
```

For a real host check, copy the runtime files (`manifest.json`, root QML/JS,
`ui/`, `assets/`, `fixtures/`, `tools/update_geoip.py`, `tools/search_city.py`) into an unused
`~/.config/omarchy/plugins/io.github.simoz.outbound/`, rescan with
`omarchy-shell shell rescanPlugins`, and enable with
`omarchy plugin enable io.github.simoz.outbound`. This changes the bar and must
be intentional. Do not overwrite an existing plugin. Summon/hide through the
normal shell IPC, and disable the temporary plugin after testing. There is no
backend required to run the simulated UI.

## Build the Ruby/Spinel collector

The default backend lives in `backend/ruby/`. Ruby handles protocol, ownership,
address scope, identity, GeoIP cache, aggregation and output bounds. Small C
adapters handle the Linux netlink ABI, blocking bounded stdin reads and libmaxminddb. The executable needs
neither a Ruby interpreter nor Rust. This is a development port, not a release
or a claim of performance parity on every architecture.

Build requirements: Linux, C compiler, `make`, `flock`, Spinel revision
`66ae8c07f2d94f86f31fe7902650e796a79895fc`, and static libmaxminddb 1.12.2.
The launcher does not download or install these tools. A local preparation
outside system directories is:

```bash
ruby_tools=$(mktemp -d /tmp/outbound-ruby-tools.XXXXXX)
git clone https://github.com/matz/spinel.git "$ruby_tools/spinel"
git -C "$ruby_tools/spinel" checkout --detach 66ae8c07f2d94f86f31fe7902650e796a79895fc
make -C "$ruby_tools/spinel" deps
make -C "$ruby_tools/spinel" -j4
git clone --depth 1 --branch 1.12.2 https://github.com/maxmind/libmaxminddb.git "$ruby_tools/maxmind"
cmake -S "$ruby_tools/maxmind" -B "$ruby_tools/maxmind/build" \
  -DBUILD_TESTING=OFF -DMAXMINDDB_BUILD_BINARIES=OFF \
  -DCMAKE_INSTALL_PREFIX="$ruby_tools/maxmind-install"
cmake --build "$ruby_tools/maxmind/build" -j4
cmake --install "$ruby_tools/maxmind/build"
export SPINEL="$ruby_tools/spinel/bin/spinel"
export MAXMIND_PREFIX="$ruby_tools/maxmind-install"
./run-ui.sh
```

Fetching tools requires network access; tests use local fixtures and loopback.
`MAXMIND_PREFIX` supplies `include/` and `lib/libmaxminddb.a`. If omitted, the
builder uses `pkg-config` to locate a system static library. `SPINEL` defaults
to `spinel` on PATH. Build output goes to ignored `backend/ruby/build/`;
`backend/ruby/build.sh --force` rebuilds even if sources are unchanged. Keep the
tool directories to rebuild after edits. An unchanged compiled binary remains
usable after they are removed.

```bash
./run-backend.sh                       # one real Ruby snapshot
backend/ruby/check.sh                  # native, Ruby and protocol checks
OUTBOUND_RUST_BACKEND="$PWD/backend/target/release/outbound-engine" \
  backend/ruby/check.sh                # also compare controlled sockets/errors
python3 -B tests/check_transport.py
python3 -B tests/check_geoip_ui.py
```

The test suite covers IPv4/IPv6 controlled endpoints, the actual UI schema,
repeated samples, PID reuse, shared descriptors, Unicode names, output/owner
bounds, scope policy, missing/corrupt/immutable GeoIP, negative caching,
shutdown and malformed input. It needs ordinary loopback/netlink access;
a sandbox denial is a failed integration check, not an empty success.

The compiled binary statically includes libmaxminddb and dynamically links
system glibc, libm and libcrypt. Redistribution must include libmaxminddb's
Apache-2.0 license/NOTICE and Spinel/runtime notices as applicable; no release
bundle or universal glibc baseline is established here. See
[Ruby validation](ruby-validation.md) for the tested environment and limits.

## Compare backend resource use on ARM64

Build both collectors first, then run the local benchmark:

```bash
python3 -B tools/benchmark_backends.py > /tmp/outbound-benchmark.json
python3 -B tools/benchmark_backends.py --pairs 256 --samples 500 --idle-seconds 10 \
  > /tmp/outbound-soak.json
```

The harness holds controlled IPv4/IPv6 loopback sockets, checks attribution and
validates the UI protocol. It reports only timings, CPU ticks, memory, descriptor
counts and aggregate counts; it does not save IPs, names or raw snapshots.
It needs ordinary netlink/loopback access and Node for protocol validation.
There are no external requests, GeoIP downloads, or desktop changes.

`--ruby` and `--rust` select existing binaries; `--reference-ruby` optionally adds
a previous Ruby binary to the same-load comparison. Samples are requested back
to back rather than at the UI's normal cadence. The tool runs without a GeoIP
database and does not measure QML rendering. See [recorded measurements and
limitations](performance.md) before interpreting latency or memory differences.

## Build and try the Rust reference collector

From the repository root, on Linux with Rust/Cargo installed:

```bash
OUTBOUND_ENGINE=rust ./run-backend.sh
```

The launcher builds the release binary when needed, requests one snapshot and
exits. It also works when invoked by absolute path from another directory.
Arguments are forwarded to the collector, for example:

```bash
OUTBOUND_ENGINE=rust ./run-backend.sh --database /path/to/country.mmdb
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

## Verify live transport and lifecycle

```bash
python3 -B tests/check_transport.py
```

Build the Ruby binary first. `OUTBOUND_TEST_NATIVE_BACKEND` can select another
executable for comparison. The test uses real Quickshell processes with
local fixture helpers, then the real collector. It checks pause/resume, view
registration, late responses, bounded retries, missing executables, malformed,
incompatible and oversized output, and shell-crash cleanup. It does not install
a plugin or print observed connection details. See
[integration-validation.md](integration-validation.md) for real-host results.

## GeoIP installer checks

```bash
python3 -B -m unittest discover -s tests -p 'test_geoip_update.py'
cargo test --manifest-path backend/Cargo.toml --locked --test geo
python3 -B tests/check_geoip_ui.py
```

The UI check requires a built Ruby backend and installed Quickshell. It uses
a synthetic local database and fixture installer, without downloads or personal
data changes. It exercises the globe button, successful reload, failure and
cancellation when the last open view closes.

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
Python is a development aid; the default runtime collector is now Ruby/Spinel.

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

The earlier [Ruby/Spinel feasibility probe](../experiments/spinel/README.md)
records ARM64/x86_64 building-block experiments. The current port lives in
`backend/ruby/` and is the default for the local launchers; those earlier
x86_64 results do not validate the full port.

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
