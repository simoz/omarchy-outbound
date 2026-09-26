"""Offline collector installer tests; archives are synthetic, never release binaries."""
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("install_engine", Path(__file__).resolve().parents[1] / "tools/install_engine.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

PREFIX = "outbound-engine-0.1.0-linux-aarch64"


def archive(entries):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as bundle:
        for name, data, kind in entries:
            member = tarfile.TarInfo(name)
            member.type = kind
            if kind == tarfile.SYMTYPE:
                member.linkname = "/etc/passwd"
                bundle.addfile(member)
            else:
                member.size = len(data)
                bundle.addfile(member, io.BytesIO(data))
    return buffer.getvalue()


def package(engine=b"#!/bin/sh\n"):
    return archive([
        (f"{PREFIX}/outbound-engine", engine, tarfile.REGTYPE),
        (f"{PREFIX}/LICENSE", b"MIT", tarfile.REGTYPE),
        (f"{PREFIX}/licenses/libmaxminddb-LICENSE", b"Apache-2.0", tarfile.REGTYPE),
    ])


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.data = Path(self.temporary.name)
        self.payload = package()
        self.fetched = []

    def release(self, payload=None):
        digest = hashlib.sha256(payload or self.payload).hexdigest()
        return {"version": "0.1.0", "assets": {"aarch64": {"name": PREFIX + ".tar.gz", "sha256": digest}}}

    def fetch(self, url, destination):
        self.fetched.append(url)
        destination.write_bytes(self.payload)

    def install(self, release=None, machine="aarch64", check=lambda engine: None):
        return installer.install(self.data, release or self.release(), machine, fetch=self.fetch, check=check)

    def current(self):
        return (self.data / "bin/outbound-engine").resolve()

    def test_install_links_verified_engine_with_notices(self):
        path, version = self.install()
        self.assertEqual(version, "0.1.0")
        self.assertTrue(path.is_symlink())
        self.assertEqual(path.read_bytes(), b"#!/bin/sh\n")
        self.assertTrue(path.stat().st_mode & 0o100)
        folder = self.current().parent
        self.assertEqual((folder / "licenses/libmaxminddb-LICENSE").read_text(), "Apache-2.0")
        self.assertIn(f"/v0.1.0/{PREFIX}.tar.gz", self.fetched[0])
        self.assertIn(hashlib.sha256(self.payload).hexdigest(), (folder / "provenance.json").read_text())
        self.assertEqual(list((self.data / "engine").glob(".download-*")), [])

    def test_reinstall_replaces_link_and_prunes_previous_version(self):
        self.install()
        previous = self.current()
        self.install()
        self.assertNotEqual(previous, self.current())
        self.assertFalse(previous.exists())
        self.assertEqual(len(list((self.data / "engine/versions").iterdir())), 1)

    def test_missing_asset_never_downloads(self):
        with self.assertRaisesRegex(ValueError, "No prebuilt collector"):
            self.install(release={"version": "0.1.0", "assets": {}})
        with self.assertRaisesRegex(ValueError, "No prebuilt collector"):
            self.install(machine="riscv64")
        self.assertEqual(self.fetched, [])

    def test_checksum_or_validation_failure_preserves_current(self):
        self.install()
        previous = self.current()
        self.payload = package(b"tampered")
        with self.assertRaisesRegex(ValueError, "pinned SHA-256"):
            self.install(release=self.release(package()))
        def failing(engine):
            raise subprocess.CalledProcessError(126, str(engine))
        with self.assertRaises(subprocess.CalledProcessError):
            self.install(check=failing)
        self.assertEqual(self.current(), previous)
        self.assertEqual(len(list((self.data / "engine/versions").iterdir())), 1)
        self.assertEqual(list((self.data / "engine").glob(".download-*")), [])

    def test_unsafe_archive_entries_are_rejected(self):
        for entries in (
            [(f"{PREFIX}/../escape", b"x", tarfile.REGTYPE)],
            [(f"{PREFIX}/outbound-engine", b"", tarfile.SYMTYPE)],
            [("other/outbound-engine", b"x", tarfile.REGTYPE)],
            [(f"{PREFIX}/LICENSE", b"MIT", tarfile.REGTYPE)],
        ):
            self.payload = archive(entries)
            with self.assertRaises(ValueError):
                self.install()
        self.assertFalse((self.data / "bin/outbound-engine").exists())
        self.assertFalse((self.data / "escape").exists())

    def test_interrupted_download_cleans_staging(self):
        def interrupted(url, destination):
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt
        with patch.object(self, "fetch", interrupted), self.assertRaises(KeyboardInterrupt):
            self.install()
        self.assertEqual(list((self.data / "engine").glob(".download-*")), [])
        self.assertFalse((self.data / "bin/outbound-engine").exists())


if __name__ == "__main__":
    unittest.main()
