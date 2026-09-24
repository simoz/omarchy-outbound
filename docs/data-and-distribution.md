# Data and distribution decisions

Phase 0 decisions, checked 2026-09-24. No geographic dataset, binary, dependency,
installer, or release artifact has been bundled or published yet.

Phase 1 update: local Natural Earth outlines are now bundled for the prototype;
see [asset provenance](../assets/NOTICE.md). No GeoIP database or Rust binary is
included. Phase 2 adds a standalone Rust collector and MMDB reader with
synthetic local test data. Source build instructions are now available in
[development.md](development.md); release installation and data distribution
remain planned.

## Geographic data

Choose **DB-IP IP to Country Lite, MMDB** for v1. The provider offers monthly
downloads under CC BY 4.0; its FAQ explicitly permits redistribution subject
to those terms. Use a local file, not its query API. Country-only lookup matches
the product scope without implying city precision.

Before distributing a database, record its release month, original download
URL, checksum and any transformation. Include “IP Geolocation by DB-IP”, a
provider link and the CC BY 4.0 link in bundled notices and a visible UI credits
surface. Preserve supplied notices and indicate modifications. Keep data
licensing separate from Outbound's MIT source licence; do not imply endorsement.
Review the full legal terms again for the actual release artifact.
Sources: [DB-IP downloads](https://db-ip.com/db/lite.php),
[FAQ](https://db-ip.com/faq.php), and [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Choose **Natural Earth 1:110m Admin 0 Countries 5.1.1** for the initial local
globe outline and country display anchors. Natural Earth's datasets are public
domain and may be modified and redistributed. Retain voluntary “Made with
Natural Earth” attribution and provenance anyway. Pin the input checksum,
record the simplification/conversion process, and bundle only the derived
geometry needed by the globe.
Sources: [dataset](https://www.naturalearthdata.com/downloads/110m-cultural-vectors/110m-admin-0-countries/)
and [terms](https://www.naturalearthdata.com/about/terms-of-use/).

A country marker is a representative display location, **not an IP coordinate**.
Label that distinction in the UI. Natural Earth uses de facto boundaries and
country geometry does not map perfectly to every ISO territory. Maintain an
explicit reviewed country-code mapping, including DB-IP's XK and unknown ZZ;
keep unmapped codes visible without inventing coordinates. Small territories
may have no polygon at this scale. No inferred exact endpoint location.

Classify loopback, private, link-local, shared/CGNAT, documentation, multicast,
unspecified and reserved/special-use addresses before GeoIP. Normalize mapped
IPv4 addresses for classification without changing their observed family.
Use pinned [IANA IPv4](https://www.iana.org/assignments/iana-ipv4-special-registry/)
and [IPv6](https://www.iana.org/assignments/iana-ipv6-special-registry/)
registries to build reviewed local rules, including exceptions; a naive
“not RFC1918 means public” test is insufficient. No runtime registry downloads.

Database missing/corrupt: retain the socket list and display unavailable
geolocation. Show database release month; initially mark it stale after 90
days (a product policy, not an accuracy guarantee). Updating is an explicit
user action outside the observation loop: validate the new file and metadata
before atomic replacement, retain the previous valid database on failure.
No auto-download on startup, panel open, or lookup miss. The origin location
is manually configured; if absent, show destination markers without origin
arcs. Do not discover public IP or location remotely.

## Packaging

The inspected `omarchy-plugin-add` clones a repository, validates its manifest,
moves it into the plugin directory and optionally enables it. It does not run
a build hook. Therefore the QML repository and the Rust executable have
separate installation steps. Adding the plugin without a backend must produce
an actionable missing-backend state, never an implicit compiler/download.

Planned release layout:

- Shared QML and geometry in the plugin repository.
- Separate archives for `x86_64-unknown-linux-gnu` and
  `aarch64-unknown-linux-gnu`, with the same protocol version.
- Build target: glibc **2.39** baseline for both architectures. Build against
  that sysroot, inspect required symbol versions and run on that baseline;
  the local glibc 2.43 probe does not validate this target.
- A versioned database asset with notices, rather than silently adding large
  monthly databases to Git history.
- Per-release checksums and verifiable signatures/attestations, source commit,
  Cargo.lock, toolchain and build-environment identity, direct/transitive
  licence notices and database provenance.

The intended explicit install step places a verified executable at
`${XDG_DATA_HOME:-~/.local/share}/outbound/bin/outbound-engine` and the verified
database at the corresponding `outbound/data/` directory. The QML service
resolves that absolute path. Source installation will use
`cargo build --release --locked` from `backend/` and copy the resulting binary
to the same location. The source build now works; the install locations and
verified release workflow remain planned and no installer is shipped.

The installer must detect architecture, reject unsupported systems, verify
artifacts before extraction and replace atomically. A checksum downloaded from
the same untrusted source alone is not an authenticity check. Builds must not
require sudo or extra capabilities to run. Rust/Cargo and Python development
tools are not runtime requirements for prebuilt releases.

Updates must pair compatible QML/backend protocol versions; an incompatible
combination displays an error and stops, rather than repeatedly restarting.
Keep the prior working executable until validation completes. Plugin removal
must stop its service; separately installed data/binaries remain unless the
user explicitly removes them. Document those paths in the eventual uninstall
instructions. No persistent socket history is written to them.

Both native runtime tests and install/update/remove checks are release gates.
Cross-compilation by itself is not ARM64 or x86_64 support certification.
Publishing releases, pushing changes and marketplace submission remain
separate actions.
