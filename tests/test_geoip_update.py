"""Offline updater tests; payloads are synthetic and not GeoIP observations."""
import gzip
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("update_geoip", Path(__file__).resolve().parents[1] / "tools/update_geoip.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.data = Path(self.temporary.name)

    @staticmethod
    def fetch(url, destination):
        destination.write_bytes(gzip.compress(b"synthetic database"))

    @staticmethod
    def validate(backend, database):
        assert database.read_bytes() == b"synthetic database"
        return {"state": "ready", "buildEpochSeconds": 1704067200, "releaseMonth": "2024-01"}

    def install(self, **kwargs):
        return updater.install(self.data, Path("/unused"), "2026-09", fetch=self.fetch, check=self.validate, **kwargs)

    def test_atomic_update_keeps_old_version_and_pairs_provenance(self):
        current = self.install()
        old = current.resolve()
        self.install()
        self.assertNotEqual(old, current.resolve())
        self.assertTrue(old.is_file())
        metadata = json.loads((current.parent / "provenance.json").read_text())
        self.assertEqual(metadata["databaseSha256"], updater.digest(current))
        self.assertEqual(metadata["license"], "CC-BY-4.0")
        self.assertIn("MIT", (current.parent / "NOTICE.txt").read_text())
        self.assertEqual(list(self.data.glob(".download-*")), [])

    def test_failed_hash_or_validation_preserves_current(self):
        previous = self.install().resolve()
        with self.assertRaises(ValueError):
            self.install(expected_sha256="0" * 64)
        with patch.object(self, "validate", side_effect=subprocess.CalledProcessError(1, "validator")):
            with self.assertRaises(subprocess.CalledProcessError):
                self.install()
        self.assertEqual((self.data / "current/country.mmdb").resolve(), previous)
        self.assertEqual(len(list((self.data / "versions").iterdir())), 1)
        self.assertEqual(list(self.data.glob(".download-*")), [])

    def test_corrupt_gzip_and_expansion_limit_preserve_current(self):
        previous = self.install().resolve()
        def corrupt(url, destination):
            destination.write_bytes(b"not gzip")
        with patch.object(self, "fetch", corrupt):
            with self.assertRaises(gzip.BadGzipFile):
                self.install()
        def expanded(url, destination):
            destination.write_bytes(gzip.compress(b"x" * 200))
        with patch.object(self, "fetch", expanded), patch.object(updater, "MAX_BYTES", 100):
            with self.assertRaisesRegex(ValueError, "Uncompressed"):
                self.install()
        self.assertEqual((self.data / "current/country.mmdb").resolve(), previous)

    def test_interrupted_download_cleans_staging_and_preserves_current(self):
        previous = self.install().resolve()
        def interrupted(url, destination):
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt
        with patch.object(self, "fetch", interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.install()
        self.assertEqual((self.data / "current/country.mmdb").resolve(), previous)
        self.assertEqual(list(self.data.glob(".download-*")), [])

    def test_failed_publish_preserves_current(self):
        previous = self.install().resolve()
        with patch.object(updater.os, "replace", side_effect=OSError("simulated publication failure")):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual((self.data / "current/country.mmdb").resolve(), previous)
        self.assertEqual(len(list((self.data / "versions").iterdir())), 1)
        self.assertEqual(list(self.data.glob(".current-*")), [])

    def test_invalid_release_never_downloads(self):
        with self.assertRaises(ValueError):
            updater.install(self.data, Path("/unused"), "../../bad")
        self.assertEqual(list(self.data.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
