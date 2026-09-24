# Outbound

See where your apps connect.

**In development — live Linux TCP snapshots.** Outbound connects a Ruby socket
collector compiled with Spinel to an Omarchy QML / Quickshell interface. Explore
observed connections by application, remote IP and country. Ownership is best-effort; partial coverage
and missing GeoIP are shown explicitly. Simulated data remains an explicit mode.

Run `./run-ui.sh` to build the Ruby collector and open an isolated live preview.
See [build requirements](docs/development.md#build-the-rubyspinel-collector) for
the pinned compiler and static libmaxminddb. An up-to-date binary needs neither
Ruby nor Spinel at runtime. `OUTBOUND_ENGINE=rust ./run-ui.sh` selects the previous
Rust collector for comparison; no automatic fallback occurs.
No plugin installation or automatic database download is performed. If GeoIP
is missing, click **Install GeoIP** on the globe. The local DB-IP Lite database
is downloaded only on request, validated and reloaded automatically. Settings
also accepts a custom MMDB and an origin chosen by city search or coordinates
for globe arcs.
Without an origin, the globe shows destination countries only.

Outbound source code is MIT. DB-IP Lite data is separately licensed under
[CC BY 4.0](https://db-ip.com/db/lite.php), with attribution in the UI and installed
notices. See [GeoIP installation and updates](docs/geoip.md).

The interface provides a bar counter, panel and expanded window, coordinated
filters, search, copy IP, keyboard help and Omarchy theme colors. The same scene
survives panel/window transitions. The earlier Rust Phase 3 integration was
checked in the real Omarchy host on ARM64; the Ruby port has controlled-socket
and isolated Quickshell checks on Linux ARM64. For the new port, x86_64 and
physical multi-monitor behavior remain unverified.

- [Architecture and shell contract](docs/architecture.md)
- [Feasibility evidence and project comparison](docs/feasibility.md)
- [Data licensing and distribution plan](docs/data-and-distribution.md)
- [Development and reproducible checks](docs/development.md)
- [Prototype validation and renderer comparison](docs/prototype-validation.md)
- [Collector protocol and bounds](docs/protocol.md)
- [Backend validation](docs/backend-validation.md)
- [Live integration validation](docs/integration-validation.md)
- [Map attribution](assets/NOTICE.md)

Connections are sampled, so short connections can be missed. Socket snapshots
do not reliably identify the initiator. GeoIP estimates are approximate; globe
arcs will represent endpoint relationships, not packet routes. No telemetry,
payload capture, active network probing, or persistent connection history is
planned.

For a local preview, follow the development guide. The runtime prototype needs
Omarchy Quattro's built-in bar and Quickshell; Python 3 is needed for the optional GeoIP installer; Node is a development
tool. Neither is needed by the socket collector. This working tree has not been published as an installable release.

Next: resource/performance validation and distribution (Phases 4–5).
