"""Explicit origin search via Photon/OpenStreetMap; no automatic geolocation."""

import json
import math
import re
import sys
import urllib.parse
import urllib.request

ENDPOINT = "https://photon.komoot.io/api/"
MAX_BYTES = 262144


def clean(value):
    return re.sub(r"[\x00-\x1f\x7f]", "", value).strip()[:120] if isinstance(value, str) else ""


def places(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get("features"), list):
        raise ValueError("Invalid search response")
    results, seen = [], set()
    for feature in payload["features"][:30]:
        if not isinstance(feature, dict):
            continue
        point, props = feature.get("geometry"), feature.get("properties")
        if not isinstance(point, dict) or point.get("type") != "Point" or not isinstance(props, dict):
            continue
        coords = point.get("coordinates")
        if not isinstance(coords, list) or len(coords) != 2 or any(type(v) not in (int, float) or not math.isfinite(v) for v in coords):
            continue
        lon, lat = coords
        if abs(lon) > 180 or abs(lat) > 90:
            continue
        name, country, region = clean(props.get("name")), clean(props.get("country")), clean(props.get("state"))
        if not name:
            continue
        label = ", ".join(dict.fromkeys(v for v in [name, region, country] if v))[:240]
        identity = (label, round(lat, 4), round(lon, 4))
        if identity in seen:
            continue
        seen.add(identity)
        results.append({"label": label, "lat": lat, "lon": lon})
        if len(results) == 6:
            break
    return results


def search(query):
    query = clean(query)
    if len(query) < 2:
        raise ValueError("Enter at least two characters")
    url = ENDPOINT + "?" + urllib.parse.urlencode({"q": query, "lang": "en", "limit": 6, "layer": "city"})
    request = urllib.request.Request(url, headers={"User-Agent": "Outbound-Origin-Search/0.1", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("Search response too large")
    return places(json.loads(raw))


def main():
    query = clean(sys.argv[1]) if len(sys.argv) == 2 else ""
    try:
        result = {"ok": True, "query": query, "places": search(query)}
    except (OSError, ValueError):
        result = {"ok": False, "query": query, "error": "City search unavailable. Try again or enter coordinates manually."}
    # ASCII output is safe across Quickshell's independently decoded chunks.
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
