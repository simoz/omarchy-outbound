# Outbound

See where your apps connect.

Outbound is an Omarchy plugin that displays observed Linux TCP connections by
application, remote IP and country, with an interactive globe. The interface
uses QML/Quickshell; the collector is Ruby compiled to a native executable with
Spinel. Only real connections are displayed.

## Features

- Bar counter, compact panel and expanded window sharing the same view state.
- Application, country and IP-family filters, text search and IP copying.
- Rotatable globe with 1×–4× zoom, country markers and connection arcs.
- Local GeoIP lookup, with an optional database download started by the user.
- Origin selection by city search or manual coordinates.
- Keyboard controls, Omarchy theme colors and reduced-motion settings.

## Requirements

- Linux and the Omarchy Quattro built-in bar with Quickshell.
- A compiled `outbound-engine` for the machine's architecture.
- Python 3.11+ for GeoIP installation and city search.

Ruby and Spinel are build tools, not runtime requirements. The current Ruby
collector and isolated Quickshell integration have been tested on Linux ARM64.
x86_64, physical multi-monitor behavior and a portable release binary remain
unverified. This repository does not provide prebuilt releases.

## Build and run

Prepare the pinned Spinel compiler and static libmaxminddb as described in the
[development guide](docs/development.md#build-the-rubyspinel-collector), then run:

```bash
./run-ui.sh
```

The launcher builds the collector when needed and opens an isolated live
preview without installing or changing the desktop bar. To use an existing
country database:

```bash
OUTBOUND_DATABASE=/absolute/path/to/country.mmdb ./run-ui.sh
```

For the installed bar widget, follow the [installation steps](docs/development.md#install-the-plugin).
The default installed collector path is
`${XDG_DATA_HOME:-$HOME/.local/share}/outbound/bin/outbound-engine`.

## Using Outbound

Open settings with the gear button:

- **Collection**: refresh interval, pause/resume, retry, coverage details and
  backend executable path.
- **Globe**: install/update GeoIP, choose a custom MMDB and set the origin.
- **Appearance**: reduced motion, glow and scanlines.
- **Credits**: data sources, attribution and licenses.

**Done** saves collection settings and closes the editor. Invalid values or a
save failure keep it open. Display options apply immediately for the session;
selecting a city saves the origin immediately.

Drag the globe to rotate it. Use the wheel, touchpad scrolling or **+/−** to
zoom. With the globe focused, arrow keys rotate, **+/−** zoom and **Home** resets
the view. The keyboard button or **F1** opens the complete shortcut guide.
Reduced motion stops rotation and arc pulses; Play can explicitly restart
rotation while keeping the arcs static.

If geolocation is missing, use **Install GeoIP**. Downloads never start
automatically. Without an origin, the globe shows destination countries without
arcs. See [GeoIP installation and updates](docs/geoip.md).

## What the data means

Connections are sampled; short-lived sockets may be missed. **PARTIAL** means
some socket or ownership information is unavailable, restricted or omitted by
resource limits. Settings → Collection shows the coverage counters.

GeoIP locations are approximate. Arcs connect the configured origin to country
markers; they are not packet routes. Connection direction is unknown. Shared
sockets may belong to several applications. The collector does not capture
payloads, infer destinations behind proxies or VPNs, or store connection history.

## Development and licenses

Build scripts, automated tests and local diagnostic tools remain in this
repository. Retired backends and feasibility experiments are available in Git
history.

- [Development, installation and tests](docs/development.md)
- [Architecture](docs/architecture.md)
- [Ruby source guide](backend/ruby/README.md)
- [Collector protocol](docs/protocol.md)
- [GeoIP data and updates](docs/geoip.md)
- [Map attribution](assets/NOTICE.md)
- [Native dependency notices](backend/DEPENDENCIES.md)

Outbound code is [MIT](LICENSE). Natural Earth geometry is public domain.
Managed DB-IP Lite data is separately licensed under CC BY 4.0; provider and
license links are available in Credits and accompany each installed database.
