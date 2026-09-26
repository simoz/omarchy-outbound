"""Explicit installation of a prebuilt collector from a pinned GitHub release."""

import argparse
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import uuid

MAX_BYTES = 32 * 1024 * 1024
RELEASES = "https://github.com/simoz/omarchy-outbound/releases/download"
RELEASE_FILE = Path(__file__).resolve().with_name("engine-release.json")
# `uname -m` spellings mapped to the architecture names used by release assets.
ARCHITECTURES = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}


class HttpsRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("Refusing a non-HTTPS redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, target):
    opener = urllib.request.build_opener(HttpsRedirect())
    deadline = time.monotonic() + 120
    total = 0
    request = urllib.request.Request(url, headers={"User-Agent": "Outbound-Engine-Installer/0.1", "Accept": "application/octet-stream"})
    with opener.open(request, timeout=15) as response, target.open("wb") as output:
        while chunk := response.read1(65536):
            total += len(chunk)
            if total > MAX_BYTES:
                raise ValueError("Release archive exceeds 32 MiB")
            if time.monotonic() > deadline:
                raise TimeoutError("Download exceeded 120 seconds")
            output.write(chunk)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def unpack(archive, prefix, target):
    """Copy regular files below `prefix` only; links, devices and escapes are rejected."""
    total = 0
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle:
            path = PurePosixPath(member.name)
            if path == PurePosixPath(prefix) and member.isdir():
                continue
            if path.is_absolute() or ".." in path.parts or path.parts[0] != prefix:
                raise ValueError(f"Unexpected archive entry: {member.name}")
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"Unsupported archive entry: {member.name}")
            total += member.size
            if total > MAX_BYTES:
                raise ValueError("Unpacked release exceeds 32 MiB")
            destination = target.joinpath(*path.parts[1:])
            destination.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, destination.open("wb") as output:
                shutil.copyfileobj(source, output)
    engine = target / "outbound-engine"
    if not engine.is_file():
        raise ValueError("Release archive does not contain outbound-engine")
    engine.chmod(0o755)
    return engine


def validate(engine):
    # --help exits without reading sockets; success proves the binary runs here.
    subprocess.run([str(engine), "--help"], check=True, capture_output=True, timeout=10)


def asset_for(release, machine):
    version = release["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Invalid collector version in engine-release.json")
    architecture = ARCHITECTURES.get(machine)
    asset = release["assets"].get(architecture) if architecture else None
    if not asset:
        raise ValueError(f"No prebuilt collector {version} for {machine}. Build it from source; see docs/development.md.")
    name = f"outbound-engine-{version}-linux-{architecture}"
    if asset["name"] != name + ".tar.gz" or not re.fullmatch(r"[0-9a-f]{64}", asset["sha256"]):
        raise ValueError("Invalid asset entry in engine-release.json")
    return version, name, asset["sha256"], f"{RELEASES}/v{version}/{name}.tar.gz"


def install(data_dir, release, machine, fetch=download, check=validate):
    version, name, expected, url = asset_for(release, machine)
    data_dir = data_dir.resolve()
    engines = data_dir / "engine"
    engines.mkdir(parents=True, exist_ok=True)
    (data_dir / "bin").mkdir(exist_ok=True)
    # Serialize explicit installs so a slower download cannot overwrite a newer one.
    with (engines / ".install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with tempfile.TemporaryDirectory(prefix=".download-", dir=engines) as temporary:
            stage = Path(temporary)
            archive = stage / "download.tar.gz"
            fetch(url, archive)
            if archive.stat().st_size > MAX_BYTES:
                raise ValueError("Release archive exceeds 32 MiB")
            if digest(archive) != expected:
                raise ValueError("Downloaded archive does not match the pinned SHA-256")
            package = stage / "package"
            engine = unpack(archive, name, package)
            archive.unlink()
            check(engine)
            metadata = {
                "version": version, "architecture": ARCHITECTURES[machine], "sourceUrl": url,
                "archiveSha256": expected, "engineSha256": digest(engine),
            }
            (package / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
            versions = engines / "versions"
            versions.mkdir(exist_ok=True)
            installed = versions / f"{version}-{uuid.uuid4().hex}"
            # Publish the binary with its notices, then switch one symlink atomically.
            package.rename(installed)
            link = data_dir / "bin" / f".outbound-engine-{uuid.uuid4().hex}"
            try:
                link.symlink_to(Path("..") / installed.relative_to(data_dir) / "outbound-engine")
                os.replace(link, data_dir / "bin" / "outbound-engine")
            except BaseException:
                link.unlink(missing_ok=True)
                shutil.rmtree(installed)
                raise
        # A running collector keeps its unlinked inode, so older versions can go.
        for previous in versions.iterdir():
            if previous != installed:
                shutil.rmtree(previous)
    return data_dir / "bin" / "outbound-engine", version


def main():
    def cancelled(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, cancelled)
    parser = argparse.ArgumentParser(description="Download, verify and install the prebuilt Outbound collector.")
    parser.add_argument("--data-dir", type=Path, default=Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "outbound")
    args = parser.parse_args()
    try:
        release = json.loads(RELEASE_FILE.read_text())
        path, version = install(args.data_dir, release, platform.machine())
    except KeyboardInterrupt:
        parser.exit(1, "Collector installation cancelled; the previous collector is unchanged.\n")
    except (OSError, ValueError, KeyError, EOFError, http.client.HTTPException, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Collector installation failed; the previous collector is unchanged: {error}\n")
    print(f"Installed collector {version}: {path}")


if __name__ == "__main__":
    main()
