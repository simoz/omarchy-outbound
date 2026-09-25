# Development

The runtime consists of the QML plugin, the compiled Ruby/Spinel collector and
optional Python helpers for city search and GeoIP installation. Node and the
Python test harness are development tools. No Ruby interpreter is needed to run
the compiled collector.

## Build the Ruby/Spinel collector

Requirements: Linux, a C compiler, `make`, `cmake`, `flock`, Spinel revision
`66ae8c07f2d94f86f31fe7902650e796a79895fc`, and static libmaxminddb 1.12.2.
Prepare tools outside system directories:

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
backend/ruby/build.sh
```

Downloads occur only during explicit tool preparation. Keep those directories to
rebuild later. `SPINEL` defaults to `spinel` on PATH; without `MAXMIND_PREFIX`, the
builder uses `pkg-config` to find a system static libmaxminddb. Build output is
ignored under `backend/ruby/build/`. Use `--force` to rebuild unchanged sources.
See the [Ruby source guide](../backend/ruby/README.md) and
[dependency notices](../backend/DEPENDENCIES.md).

## Run the live interface

```bash
./run-ui.sh
OUTBOUND_DATABASE=/absolute/path/to/country.mmdb ./run-ui.sh
```

The launcher rebuilds when sources change and opens a fresh isolated preview.
`OUTBOUND_BACKEND` can explicitly select another compatible executable. The
launcher overrides any backend path saved by an earlier preview.

The preview uses installed Omarchy `Commons`/`Ui` modules, but a simulated host:
it does not install a plugin or change the bar. It collects real sockets and
has no demo mode. Saved preview settings live in
`${XDG_CONFIG_HOME:-$HOME/.config}/outbound/preview.ini`.
`OUTBOUND_BACKEND` and `OUTBOUND_DATABASE` override saved paths.

To request one real snapshot from the terminal:

```bash
./run-backend.sh
./run-backend.sh --database /absolute/path/to/country.mmdb
```

## Install the plugin

Build the collector first. Place its executable at the default runtime path:

```bash
install -Dm755 backend/ruby/build/outbound-engine \
  "${XDG_DATA_HOME:-$HOME/.local/share}/outbound/bin/outbound-engine"
```

Copy these files into an **unused**
`~/.config/omarchy/plugins/io.github.simoz.outbound/` directory, preserving paths:

- `manifest.json`, `LICENSE`, root `*.qml` and `*.js` files.
- `ui/` and `assets/`.
- `tools/search_city.py` and `tools/update_geoip.py`.

Then validate and enable the plugin:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.simoz.outbound
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.simoz.outbound
```

Enabling changes the desktop bar. Do not overwrite an existing installation
without preserving its configuration. The runtime does not build or download
a collector automatically. A custom absolute executable path can be saved in
Settings → Collection. Installed collection settings use the host's inline
plugin configuration; Appearance settings are session-only.

The bar alone samples every 10 seconds. An open panel/window uses the configured
1–60 second interval. Pause survives view transitions. Removing every registered
view stops collection; closing the last open view cancels helper downloads and
city searches. See [architecture](architecture.md).

## Origin and GeoIP

Settings → Globe contains city search, manual coordinates and GeoIP controls.
Search or Enter sends an explicit query to Photon/OpenStreetMap; typing does
not contact the provider. Choosing a result saves the origin immediately.
**Done** saves manual coordinates; clear both coordinates to remove the origin.

Search is limited to six results, cached for the session (20 queries) and spaced
by at least 1.1 seconds. Changing the query, closing settings or closing the last
view cancels the search and ignores late replies. Queries contain the city text,
never observed IPs or process names. Manual coordinates work without a lookup.

No database is bundled. Use **Install GeoIP** or **Install / update managed
GeoIP** to download and validate one explicitly. A custom MMDB path overrides
the managed database. See [GeoIP details](geoip.md).

## Automated checks

With the build tool environment above:

```bash
backend/ruby/check.sh
node --test tests/*.test.cjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
  /usr/lib/qt6/bin/qmltestrunner -input tests -import tests/stubs -o -,txt
python3 -B tests/check_transport.py
python3 -B tests/check_geoip_ui.py
python3 -B tests/check_origin_search.py
python3 -B tests/check_preview_settings.py
omarchy plugin validate .
git diff --check
```

The backend suite covers native framing, protocol validation, process identity,
shared descriptors, Unicode, scope, synthetic GeoIP, bounds and controlled
IPv4/IPv6 sockets. Socket tests need ordinary loopback/netlink access. A sandbox
permission failure is not a passing integration test.

QtTest uses a minimal `qs.Commons` facade. The Python integration scripts use
real Quickshell and local helpers without modifying personal settings or
contacting public providers. Synthetic connection data lives in `tests/fixtures/`
and is never copied into the runtime. Physical multi-monitor behavior and the
real bar still require testing in the installed host.

## Visual checks

Assemble a fresh preview after source changes:

```bash
outbound_preview=$(python3 -B tools/prepare_preview.py)
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
  OUTBOUND_THEME=light OUTBOUND_CAPTURE=/tmp/outbound-light.png \
  qs -p "$outbound_preview"
```

Supported controls: `OUTBOUND_THEME` (`light`/`dark`, otherwise the installed
theme), `OUTBOUND_WIDTH`, `OUTBOUND_HEIGHT`, `OUTBOUND_RENDERER`
(`canvas`/`shapes`) and `OUTBOUND_BENCHMARK=1`. The benchmark rotates the globe
for 120 ticks and reports timings and idle repaint counts; these are not GPU
frame-rate guarantees. A normal preview uses real connections: inspect captures
before sharing them. Offscreen rendering is not a real desktop integration test.

## Performance and manual connections

Measure the current collector using controlled local sockets:

```bash
python3 -B tools/benchmark_backends.py --samples 30
# Compare a previously built Ruby binary:
python3 -B tools/benchmark_backends.py --reference-ruby /path/to/previous/outbound-engine
```

The harness reports aggregate timings, CPU, memory, descriptors and counts;
it does not save observed IPs, names or raw snapshots. No external requests are
made. `--pairs`, `--samples` and `--idle-seconds` control the workload.

For a deliberate live HTTPS test, run `./test-connections.sh` with the UI open.
It sends HEAD requests to up to five public targets for two minutes, reconnecting
at most once every five seconds. Ctrl+C stops it. Filter by `python3`; DNS/CDNs
determine the actual countries. This manual helper is not part of the offline
suite. `--duration` and `--host` select duration and targets.
