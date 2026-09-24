# Outbound

See where your apps connect.

**In development — UI uses simulated data.** Outbound is an Omarchy QML / Quickshell
prototype for exploring connections by application, remote IP, and country on
an interactive globe. A standalone Rust collector and local MMDB reader are
implemented, but are not yet connected to the UI. Nothing in the UI represents your actual traffic.

The prototype provides a compact bar counter, a panel and an expanded window,
coordinated country/application/IP-family filters, search and copy IP. It follows the Omarchy theme, supports keyboard navigation and
reduced motion, and includes sample, empty, error and large-dataset scenarios.
The same scene survives panel/window transitions.

Phase 0 and the initial Phase 1 prototype are complete. Loading, expansion,
collapse and reopen were checked in the real Omarchy host on ARM64. Light/dark
and narrow-layout checks used an isolated preview. x86_64 and multi-monitor
integration are not yet verified.

- [Architecture and shell contract](docs/architecture.md)
- [Feasibility evidence and project comparison](docs/feasibility.md)
- [Data licensing and distribution plan](docs/data-and-distribution.md)
- [Development and reproducible checks](docs/development.md)
- [Prototype validation and renderer comparison](docs/prototype-validation.md)
- [Collector protocol and bounds](docs/protocol.md)
- [Backend validation](docs/backend-validation.md)
- [Map attribution](assets/NOTICE.md)

Connections are sampled, so short connections can be missed. Socket snapshots
do not reliably identify the initiator. GeoIP estimates are approximate; globe
arcs will represent endpoint relationships, not packet routes. No telemetry,
payload capture, active network probing, or persistent connection history is
planned.

For a local preview, follow the development guide. The runtime prototype needs
Omarchy Quattro's built-in bar and Quickshell; Python and Node are development
tools only. This working tree has not been published as an installable release.

Next: connect the standalone collector to the QML service (Phase 3).
