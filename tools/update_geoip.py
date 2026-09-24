"""Explicit DB-IP Lite installation; Python is an installation tool only."""

import argparse
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import signal
import time
import urllib.request
import subprocess
import tempfile
import uuid
import zlib

MAX_BYTES = 64 * 1024 * 1024
PROVIDER = "https://db-ip.com/db/lite.php"
LICENSE = "https://creativecommons.org/licenses/by/4.0/"


class HttpsRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("Refusing a non-HTTPS redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, target):
    opener = urllib.request.build_opener(HttpsRedirect())
    deadline = time.monotonic() + 120
    total = 0
    request = urllib.request.Request(url, headers={"User-Agent": "Outbound-GeoIP-Updater/0.1", "Accept": "application/octet-stream"})
    with opener.open(request, timeout=15) as response, target.open("wb") as output:
        while chunk := response.read1(65536):
            total += len(chunk)
            if total > MAX_BYTES:
                raise ValueError("Compressed database exceeds 64 MiB")
            if time.monotonic() > deadline:
                raise TimeoutError("Download exceeded 120 seconds")
            output.write(chunk)


def unpack(archive, target):
    total = 0
    with gzip.open(archive, "rb") as source, target.open("wb") as output:
        while chunk := source.read(65536):
            total += len(chunk)
            if total > MAX_BYTES:
                raise ValueError("Uncompressed database exceeds 64 MiB")
            output.write(chunk)
        output.flush()
        os.fsync(output.fileno())


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def validate(backend, database):
    result = subprocess.run(
        [str(backend), "--check-database", "--database", str(database)],
        check=True, capture_output=True, text=True, timeout=30,
    )
    return json.loads(result.stdout)


def install(data_dir, backend, month, expected_sha256=None, fetch=download, check=validate):
    if not re.fullmatch(r"[0-9]{4}-(0[1-9]|1[0-2])", month):
        raise ValueError("Release must be YYYY-MM")
    if expected_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha256):
        raise ValueError("SHA-256 must contain 64 hexadecimal digits")
    data_dir = data_dir.resolve()
    data_dir.mkdir(parents=True, exist_ok=True)
    url = f"https://download.db-ip.com/free/dbip-country-lite-{month}.mmdb.gz"
    # Serialize explicit updates so a slower download cannot overwrite a newer one.
    with (data_dir / ".update.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with tempfile.TemporaryDirectory(prefix=".download-", dir=data_dir) as temporary:
            stage = Path(temporary)
            archive = stage / "download.gz"
            fetch(url, archive)
            if archive.stat().st_size > MAX_BYTES:
                raise ValueError("Compressed database exceeds 64 MiB")
            archive_hash = digest(archive)
            if expected_sha256 and archive_hash != expected_sha256.lower():
                raise ValueError("Downloaded archive does not match the supplied SHA-256")
            database = stage / "country.mmdb"
            unpack(archive, database)
            status = check(backend, database)
            if status["state"] != "ready":
                raise ValueError("Database validation failed")
            metadata = {
                "provider": "DB-IP", "edition": "IP to Country Lite", "releaseMonth": month,
                "sourceUrl": url, "downloadedAt": datetime.now(timezone.utc).isoformat(),
                "archiveSha256": archive_hash, "databaseSha256": digest(database),
                "buildEpochSeconds": status["buildEpochSeconds"],
                "buildMonth": status["releaseMonth"], "license": "CC-BY-4.0",
                "licenseUrl": LICENSE, "attribution": "IP Geolocation by DB-IP",
                "transformation": "Gzip decompression only; MMDB contents unchanged",
            }
            (stage / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
            (stage / "NOTICE.txt").write_text(
                f"IP Geolocation by DB-IP\n{PROVIDER}\n"
                f"DB-IP IP to Country Lite, release {month}\n"
                f"Creative Commons Attribution 4.0 International (CC BY 4.0)\n{LICENSE}\n"
                "Gzip decompression only; database contents unchanged.\n"
                "Outbound source code is MIT; this dataset is separately licensed.\n"
                "See provenance.json for the source URL and SHA-256 checksums.\n"
            )
            archive.unlink()
            versions = data_dir / "versions"
            versions.mkdir(exist_ok=True)
            version = versions / f"dbip-country-lite-{month}-{uuid.uuid4().hex}"
            # Publish database, notices and provenance as a single directory, then
            # switch one symlink atomically. Old versions remain available.
            stage.rename(version)
            link = data_dir / f".current-{uuid.uuid4().hex}"
            try:
                link.symlink_to(version.relative_to(data_dir), target_is_directory=True)
                os.replace(link, data_dir / "current")
            except BaseException:
                link.unlink(missing_ok=True)
                shutil.rmtree(version)
                raise
    return data_dir / "current" / "country.mmdb"


def main():
    def cancelled(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, cancelled)
    parser = argparse.ArgumentParser(description="Download and validate DB-IP Country Lite (CC BY 4.0). No scheduled updates.")
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument("--month", default=datetime.now(timezone.utc).strftime("%Y-%m"))
    parser.add_argument("--sha256", help="Expected SHA-256 of the compressed archive, if independently obtained")
    parser.add_argument("--data-dir", type=Path, default=Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "outbound/data")
    args = parser.parse_args()
    try:
        path = install(args.data_dir, args.backend.resolve(), args.month, args.sha256)
    except KeyboardInterrupt:
        parser.exit(1, "GeoIP update cancelled; the previous database is unchanged.\n")
    except (OSError, ValueError, KeyError, EOFError, http.client.HTTPException, zlib.error, subprocess.SubprocessError) as error:
        parser.exit(1, f"GeoIP update failed; the previous database is unchanged: {error}\n")
    print(f"Installed: {path}\nIP Geolocation by DB-IP · CC BY 4.0\nStart Outbound or press Retry in settings to reload.")


if __name__ == "__main__":
    main()
