# GeoIP installation and updates

Outbound code is MIT. The managed **DB-IP IP to Country Lite** dataset is
**CC BY 4.0**, separately from the application. IP Geolocation by DB-IP:
[provider and terms](https://db-ip.com/db/lite.php),
[license](https://creativecommons.org/licenses/by/4.0/).
No provider database is included in the repository or relicensed as MIT.

## From the interface

Open Outbound (or `./run-ui.sh`), then click **Install GeoIP** on the globe when
geolocation is unavailable. A collector must be installed first; see
[collector installation](development.md#prebuilt-collector). The button shows download/validation activity and any failure.
Success reloads the backend automatically and hides the installation prompt.
Settings provides **Install / update managed GeoIP** for subsequent monthly
updates. Installing managed data selects it if the custom path was not changed
while installation was running. The origin remains manually configured.

The updater needs Python 3.11+ and an installed or built backend with `--check-database` support.
It runs only after an explicit click. Closing the last panel/window cancels installation; keeping only the bar does not keep a
download alive. The ordinary collector makes no GeoIP network requests.

## From the terminal

```bash
./update-geoip.sh
# Choose a published release explicitly:
./update-geoip.sh --month 2026-09
# Optional independently obtained archive checksum:
./update-geoip.sh --month 2026-09 --sha256 EXPECTED_SHA256
```

The wrapper builds the validator before invoking the Python installer. By
default it requests the current UTC month; unavailable releases produce an
error without falling back silently. CLI updates require restarting Outbound
or pressing **Retry** in settings to reload an already running collector.
Use `--data-dir /absolute/path` for an isolated installation. The UI uses the
standard managed location unless a custom MMDB path is configured.

## Storage, validation and privacy

Files live under `${XDG_DATA_HOME:-$HOME/.local/share}/outbound/data/`:

- `versions/dbip-country-lite-YYYY-MM-ID/`: unmodified decompressed `country.mmdb`,
  `NOTICE.txt` and `provenance.json` with provider URL, requested release, build
  timestamp, download time, license and compressed/uncompressed SHA-256 hashes.
- `current`: an atomically replaced relative symlink to a validated version.

Prior versions remain on disk. Failed downloads, decompression, validation or
publication leave the current version intact. Updates are serialized with a
local lock. Nothing deletes old versions automatically. The custom MMDB field
can select an older version directly if needed.

Downloads use verified HTTPS with HTTPS-only redirects, a 15-second socket
timeout and a 120-second download deadline checked between reads. Compressed
and uncompressed files are bounded to 64 MiB. Validation has a 30-second timeout
and invokes the selected backend's reader, including structural and
build-timestamp validation. The Ruby backend uses libmaxminddb over a sealed
local copy. Hashes record provenance; locally computed hashes
are not independent provider signatures. An optional expected SHA-256 rejects
mismatched archives before decompression.

The request downloads a complete country database; no observed connection IPs,
process names or origin coordinates are sent to DB-IP. Country markers remain
approximate. Unknown or unmapped countries remain visible in the connection
list. Attribution is available in Settings → Credits,
and accompanies every installed version.

## Verification

Offline updater tests cover atomic replacement, retained previous versions,
checksum mismatch, corrupt gzip, decompression limits and validation failures.
The Ruby backend suite validates synthetic country databases and rejects invalid
metadata or corruption. Quickshell fixture checks cover installation/reload,
visible failures and cancellation. See [test commands](development.md#automated-checks).
