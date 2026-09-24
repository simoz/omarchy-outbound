# Outbound

See where your apps connect.

**In development.** Outbound is a planned Omarchy plugin for exploring observed
TCP connections by application, remote IP, and estimated country on a globe.
The intended runtime is QML / Quickshell with a Rust collector and local GeoIP.
There is no installable plugin or Rust backend yet.

Phase 0 (contracts and feasibility) is complete. The unprivileged socket probe
passed on Linux ARM64; desktop integration and x86_64 support are not yet tested.

- [Architecture and shell contract](docs/architecture.md)
- [Feasibility evidence and project comparison](docs/feasibility.md)
- [Data licensing and distribution plan](docs/data-and-distribution.md)
- [Development and reproducible checks](docs/development.md)

Connections are sampled, so short connections can be missed. Socket snapshots
do not reliably identify the initiator. GeoIP estimates are approximate; globe
arcs will represent endpoint relationships, not packet routes. No telemetry,
payload capture, active network probing, or persistent connection history is
planned.

Next: a theme-aware QML prototype with clearly labelled simulated data.
