"""Offline Photon response validation and request-bound tests."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("city", Path(__file__).resolve().parents[1] / "tools/search_city.py")
city = importlib.util.module_from_spec(spec)
spec.loader.exec_module(city)


def feature(name="Test city", coords=None):
    return {"geometry": {"type": "Point", "coordinates": coords if coords is not None else [8.9, 44.4]}, "properties": {"name": name, "state": "Region", "country": "Italy"}}


class CityTests(unittest.TestCase):
    def test_places_validate_coordinates_deduplicate_and_limit_results(self):
        invalid = [None, feature(coords=[True, 0]), feature(coords=[181, 0]), feature(coords=[0, float("nan")]), feature(name="")]
        result = city.places({"features": invalid + [feature(), feature()] + [feature(str(i)) for i in range(10)]})
        self.assertEqual(len(result), 6)
        self.assertEqual(result[0], {"label": "Test city, Region, Italy", "lat":44.4, "lon":8.9})
        with self.assertRaises(ValueError):
            city.places({"features": {}})

    def test_query_is_encoded_and_response_is_bounded(self):
        with patch.object(city.urllib.request, "urlopen", return_value=io.BytesIO(b'{"features":[]}')) as request:
            self.assertEqual(city.search("Roma & Lazio"), [])
            url = request.call_args.args[0].full_url
            self.assertIn("q=Roma+%26+Lazio", url)
            self.assertIn("layer=city", url)
            self.assertEqual(request.call_args.kwargs["timeout"], 10)
        with patch.object(city.urllib.request, "urlopen", return_value=io.BytesIO(b"x" * (city.MAX_BYTES + 1))):
            with self.assertRaisesRegex(ValueError, "too large"):
                city.search("Test")
        with patch.object(city.urllib.request, "urlopen") as request:
            with self.assertRaises(ValueError):
                city.search(" ")
            request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
