#!/usr/bin/env python3
"""Build the plugin's bundled map data from saved, public source catalogs.

This is an offline development tool. It uses only Python's standard library and
never fetches data or calls NordVPN. The source directory must contain:
  countries-50m.geojson, states50m-us.geojson, nord-countries.json

The fallback may be a normalized city JSON array, a Natural Earth populated
places GeoJSON file, or locationData.js containing fallbackCities (or cities).
When available, source-manifest.json is copied to mapSources.json; otherwise an
existing mapSources.json remains untouched. Use --source-manifest to choose an
explicit provenance manifest.
"""

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def polygons(geometry):
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    raise ValueError(f"Unsupported geometry type: {geometry['type']}")


def inside(point, ring):
    x, y = point
    result = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (a[1] > y) != (b[1] > y) and x < (
            (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
        ):
            result = not result
    return result


def in_polygon(point, rings):
    return inside(point, rings[0]) and not any(
        inside(point, ring) for ring in rings[1:]
    )


def area(ring):
    return abs(
        sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:] + ring[:1]))
    ) / 2


def interior(rings):
    """Find the longest interior interval on sampled latitude scan lines."""
    ys = [point[1] for point in rings[0]]
    low, high = min(ys), max(ys)
    middle = (low + high) / 2
    best = None
    for y in [middle] + [low + (high - low) * step / 10 for step in range(1, 10)]:
        intersections = []
        for ring in rings:
            for a, b in zip(ring, ring[1:] + ring[:1]):
                if (a[1] > y) != (b[1] > y):
                    intersections.append(
                        a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
                    )
        intersections.sort()
        for low_x, high_x in zip(intersections[::2], intersections[1::2]):
            point = ((low_x + high_x) / 2, y)
            if in_polygon(point, rings) and (
                best is None or high_x - low_x > best[0]
            ):
                best = (high_x - low_x, point)
    if best is None:
        raise ValueError("Could not find an interior country anchor")
    return best[1]


def normalize(point):
    return [round((point[0] + 180) / 360, 7), round((90 - point[1]) / 180, 7)]


def bounds(points):
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def distance_squared(point, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    if dx or dy:
        dot = (point[0] - a[0]) * dx + (point[1] - a[1]) * dy
        position = max(0, min(1, dot / (dx * dx + dy * dy)))
    else:
        position = 0
    return (point[0] - a[0] - position * dx) ** 2 + (
        point[1] - a[1] - position * dy
    ) ** 2


def simplify(points, tolerance):
    if len(points) <= 4:
        return points
    keep = {0, len(points) - 1}
    stack = [(0, len(points) - 1)]
    while stack:
        start, end = stack.pop()
        maximum = tolerance * tolerance
        index = None
        for i in range(start + 1, end):
            distance = distance_squared(points[i], points[start], points[end])
            if distance > maximum:
                maximum, index = distance, i
        if index is not None:
            keep.add(index)
            stack.extend([(start, index), (index, end)])
    result = [points[i] for i in sorted(keep)]
    return result if len(result) >= 4 else points


def packed(rings):
    raw = [[normalize(point) for point in ring] for ring in rings]
    return {
        "bounds": bounds(raw[0]),
        "rings": raw,
        "overview": [simplify(ring, 0.00065) for ring in raw],
    }


def nord_cities(catalog):
    cities = []
    for country in catalog:
        subdivisions = {
            subdivision["id"]: subdivision["name"]
            for subdivision in country.get("subdivisions", [])
        }
        for city in country["cities"]:
            cities.append(
                {
                    "country": country["name"].replace(" ", "_"),
                    "countryCode": country["code"],
                    "city": city["name"].replace(" ", "_"),
                    "label": city["name"],
                    "region": subdivisions.get(city.get("subdivision_id"), ""),
                    "lon": city["longitude"],
                    "lat": city["latitude"],
                    "source": "nordvpn",
                }
            )
    return cities


def fallback_cities(path):
    if path.suffix.lower() == ".js":
        text = path.read_text(encoding="utf-8")
        match = re.search(r"\bvar\s+fallbackCities\s*=\s*", text)
        if match is None:
            match = re.search(r"\bvar\s+cities\s*=\s*", text)
        if match is None:
            raise ValueError(f"No fallbackCities or cities variable in {path}")
        data, _ = json.JSONDecoder().raw_decode(text[match.end():])
    else:
        data = read_json(path)
    if isinstance(data, dict) and data.get("type") == "FeatureCollection":
        features = sorted(
            data["features"],
            key=lambda feature: feature["properties"].get(
                "pop_max", feature["properties"].get("POP_MAX", 0)
            ) or 0,
            reverse=True,
        )
        data = []
        for feature in features:
            properties = {key.lower(): value for key, value in feature["properties"].items()}
            country = properties.get("adm0name") or properties.get("sov0name")
            city = properties.get("nameascii") or properties.get("name")
            if not country or not city or feature["geometry"]["type"] != "Point":
                continue
            lon, lat = feature["geometry"]["coordinates"][:2]
            data.append(
                {
                    "country": country.replace(" ", "_"),
                    "city": city.replace(" ", "_"),
                    "label": properties.get("name") or city,
                    "region": properties.get("adm1name") or "",
                    "lon": lon,
                    "lat": lat,
                }
            )
    elif isinstance(data, dict):
        data = data.get("fallbackCities", data.get("cities"))
    if not isinstance(data, list):
        raise ValueError(f"Expected a city array or populated places GeoJSON in {path}")
    for city in data:
        city.pop("population", None)
        city["source"] = "natural-earth"
    return data


def country_data(features, catalog):
    country_api = {country["code"]: country for country in catalog}
    primary = {}
    for feature in features:
        code = feature["properties"]["ISO_A2_EH"]
        size = sum(area(rings[0]) for rings in polygons(feature["geometry"]))
        if code not in primary or size > primary[code][0]:
            primary[code] = (size, feature)
    countries, geometry = [], []
    for feature in features:
        properties = feature["properties"]
        code = properties["ISO_A2_EH"]
        raw = polygons(feature["geometry"])
        largest = max(raw, key=lambda rings: area(rings[0]))
        lon, lat = properties["LABEL_X"], properties["LABEL_Y"]
        anchor = "label"
        if not any(in_polygon((lon, lat), rings) for rings in raw):
            lon, lat = interior(largest)
            anchor = "interior"
        aliases = [
            properties[name]
            for name in ["NAME", "NAME_LONG", "ADMIN", "FORMAL_EN", "NAME_EN", "SOVEREIGNT", "BRK_NAME"]
            if properties.get(name)
        ]
        # Dependencies sharing a sovereign must keep their own country name.
        aliases = [
            value for value in aliases
            if value != properties.get("SOVEREIGNT")
            or value in [properties.get("NAME"), properties.get("NAME_LONG"), properties.get("ADMIN")]
        ]
        api = country_api.get(code) if primary[code][1] is feature else None
        if api:
            aliases.append(api["name"])
        countries.append(
            {
                "id": properties["ADM0_A3"],
                "official": api is not None,
                "code": code,
                "name": api["name"] if api else properties["NAME_LONG"],
                "aliases": sorted(set(aliases)),
                "lon": round(lon, 7),
                "lat": round(lat, 7),
                "bounds": packed(largest)["bounds"],
                "anchorSource": anchor,
            }
        )
        geometry.append(
            {"id": properties["ADM0_A3"], "code": code, "polygons": [packed(rings) for rings in raw]}
        )
    return countries, geometry


def state_data(features):
    states = []
    for feature in features:
        properties = feature["properties"]
        raw = polygons(feature["geometry"])
        states.append(
            {
                "name": properties["name"],
                "code": properties["postal"],
                "lon": properties["longitude"],
                "lat": properties["latitude"],
                "polygons": [packed(rings) for rings in raw],
                "bounds": bounds([normalize(vertex) for rings in raw for vertex in rings[0]]),
            }
        )
    return states


def write_library(path, variables, comment):
    text = ".pragma library\n// " + comment + "\n"
    for name, value in variables.items():
        text += "var " + name + " = " + json.dumps(value, separators=(",", ":"), allow_nan=False) + ";\n"
    path.write_text(text, encoding="utf-8")


def build(source_dir, fallback_path, output_dir, manifest_path=None):
    catalog = read_json(source_dir / "nord-countries.json")
    countries, geometry = country_data(
        read_json(source_dir / "countries-50m.geojson")["features"], catalog
    )
    cities = nord_cities(catalog)
    fallback = fallback_cities(fallback_path)
    states = state_data(read_json(source_dir / "states50m-us.geojson")["features"])
    manifest_text = manifest_path.read_text(encoding="utf-8") if manifest_path else None
    manifest = json.loads(manifest_text) if manifest_text else {}
    retrieval = manifest.get("nordCatalog", {}).get("retrievedAt")
    catalog_note = "NordVPN anonymous country/city catalog"
    if retrieval:
        date = datetime.fromisoformat(retrieval.replace("Z", "+00:00"))
        if date.tzinfo is None:
            raise ValueError("Catalog retrievedAt must specify a timezone")
        catalog_note += " (" + date.astimezone(timezone.utc).date().isoformat() + " UTC)"
    geometry_note = "Natural Earth 1:50m country coastlines and borders"
    commit = manifest.get("naturalEarth", {}).get("commit")
    if commit:
        geometry_note += "; pinned " + commit
    output_dir.mkdir(parents=True, exist_ok=True)
    write_library(
        output_dir / "locationData.js",
        {"countries": countries, "cities": cities, "fallbackCities": fallback, "states": states},
        catalog_note + "; Natural Earth public-domain fallback.",
    )
    write_library(output_dir / "mapData.js", {"countries": geometry}, geometry_note + ".")
    if manifest_text is not None:
        (output_dir / "mapSources.json").write_text(manifest_text, encoding="utf-8")
    print(f"Generated {len(countries)} country anchors, {len(cities)} official cities, {len(states)} U.S. states/districts")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-dir", required=True, type=Path, help="Directory with the three saved source catalogs")
    parser.add_argument("--fallback", required=True, type=Path, help="City JSON/GeoJSON or locationData.js file")
    parser.add_argument("--output-dir", required=True, type=Path, help="Destination directory for generated QML JavaScript data")
    parser.add_argument("--source-manifest", type=Path, help="Provenance JSON; defaults to source-dir/source-manifest.json if present")
    args = parser.parse_args()
    manifest = args.source_manifest
    if manifest is None:
        candidate = args.source_dir / "source-manifest.json"
        manifest = candidate if candidate.is_file() else None
    try:
        build(args.source_dir, args.fallback, args.output_dir, manifest)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
