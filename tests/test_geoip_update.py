"""Offline updater tests; payloads are synthetic and not GeoIP observations."""
from datetime import datetime, timezone
import fcntl
import gzip
import importlib.util
import json
from pathlib import Path
import subprocess
import urllib.error
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

    def test_update_keeps_previous_version_and_prunes_older(self):
        first = self.install().resolve().parent
        second = self.install().resolve().parent
        third = self.install().resolve().parent
        self.assertFalse(first.exists())
        self.assertEqual(sorted((self.data / "versions").iterdir()), sorted([second, third]))
        self.assertEqual((self.data / "current/country.mmdb").resolve().parent, third)

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

    def http_error(self, url, code):
        error = urllib.error.HTTPError(url, code, "Synthetic", {}, None)
        self.addCleanup(error.close)
        return error

    def test_unpublished_current_month_falls_back_to_previous_only(self):
        requested = []
        def fetch(url, destination):
            requested.append(url)
            if "2026-01" in url:
                raise self.http_error(url, 404)
            self.fetch(url, destination)
        current = updater.install_latest(self.data, Path("/unused"), datetime(2026, 1, 1, tzinfo=timezone.utc), fetch=fetch, check=self.validate)
        self.assertEqual([url.rsplit("-", 2)[-2:] for url in requested], [["2026", "01.mmdb.gz"], ["2025", "12.mmdb.gz"]])
        self.assertEqual(json.loads((current.parent / "provenance.json").read_text())["releaseMonth"], "2025-12")

    def test_other_download_errors_do_not_fall_back(self):
        requested = []
        def fetch(url, destination):
            requested.append(url)
            raise self.http_error(url, 503)
        with self.assertRaises(urllib.error.HTTPError):
            updater.install_latest(self.data, Path("/unused"), datetime(2026, 9, 15, tzinfo=timezone.utc), fetch=fetch, check=self.validate)
        self.assertEqual(len(requested), 1)

    def test_explicit_unpublished_month_is_unavailable(self):
        def missing(url, destination):
            raise self.http_error(url, 404)
        with patch.object(self, "fetch", missing), self.assertRaises(updater.Unavailable):
            self.install()
        self.assertEqual(list(self.data.glob(".download-*")), [])

    def test_concurrent_update_is_busy(self):
        self.data.mkdir(exist_ok=True)
        with (self.data / ".update.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with self.assertRaises(updater.Busy):
                self.install()

    def test_missing_collector_is_reported(self):
        with self.assertRaises(updater.NoCollector):
            updater.validate(self.data / "missing-engine", self.data / "country.mmdb")

    def test_invalid_release_never_downloads(self):
        with self.assertRaises(ValueError):
            updater.install(self.data, Path("/unused"), "../../bad")
        self.assertEqual(list(self.data.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
