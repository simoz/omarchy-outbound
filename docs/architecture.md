# Architecture

Outbound targets the Omarchy Quattro built-in bar and Quickshell. The plugin ID
is `io.github.simoz.outbound`; `Service.qml` and `BarWidget.qml` are the manifest
entry points. The repository contains one collector implementation: Ruby
compiled with Spinel, with small C adapters for Linux and libmaxminddb.

## Interface and lifecycle

- `BarWidget.qml` registers the host view and opens `Panel.qml`.
- `Panel.qml` keeps one `Dashboard` scene when switching between compact and
  expanded views, preserving filters, selection and globe camera state.
- `Service.qml` owns settings, filters and observed rows across views.
- `Collector.qml` owns the single backend process, snapshot requests, bounded
  framing, retry state and the lifecycle of the explicit installers (prebuilt
  collector and GeoIP), which never run concurrently.
- `OriginSearch.qml` runs explicit city searches, caches results and rejects
  cancelled or stale replies.
- `ui/Globe.qml` draws local geometry and observed destination markers using
  orthographic projection. Zoom and rotation update the same projection for
  outlines, arcs and markers. Rendering components do not make network requests.

Registered bar views keep collection active at a 10-second interval. Open
panels/windows use the configured interval; manual pause stops collection.
Removing all registered views stops the backend. Helper downloads/searches need
an open view and are cancelled when the last one closes.

## Data flow

The UI requests complete snapshots over the backend's stdin. The backend dumps
connected TCP sockets for IPv4 and IPv6, joins readable `/proc` owners, applies
local GeoIP and writes bounded JSON lines. `Protocol.js` validates framing,
contents, aggregates and sequence/session information before updating the model.

Only one snapshot request is outstanding. Timeouts, bounded retries and process
replacement are coordinated by the transport; late replies cannot replace newer
state. See the [protocol](protocol.md) for limits and failure handling, and the
[Ruby source guide](../backend/ruby/README.md) for internal responsibilities.

## Observation limits

A socket is counted once globally. Multiple application owners can overlap in
application totals. PID/start-time checks prevent attribution across detected
PID reuse; snapshots are not atomic and cannot prove connection direction.
Unobservable owners remain unknown. Collection stays within the current network
namespace and readable process metadata; it does not enter containers or infer
remote endpoints behind VPNs/proxies.

Country markers are approximate display anchors, not exact host locations.
Arcs connect a manually configured origin to those markers without claiming
packet routes. Missing GeoIP never removes connection rows. No database, origin
or connection history is downloaded or persisted automatically.
