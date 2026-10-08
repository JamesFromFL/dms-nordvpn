"""Geographic integrity checks for the shipped map data; no VPN or network access.

Run with: python3 -m unittest discover -s tests -p 'test_map_data.py'
The city reference coordinates below are from NordVPN's countries API,
https://api.nordvpn.com/v1/servers/countries, retrieved 2026-10-08 UTC.
"""

import json
import math
from pathlib import Path
import re
import unicodedata
import unittest


PLUGIN = Path(__file__).resolve().parents[1]
EPSILON = 0.00000011  # Geometry is normalized and rounded to seven decimals.


def read_assignment(filename, variable):
    """Read JSON data without executing the QML JavaScript library."""
    source = (PLUGIN / filename).read_text(encoding="utf-8")
    match = re.search(r"^var " + re.escape(variable) + r"\s*=\s*", source, re.M)
    if match is None:
        raise ValueError(f"Missing {variable} in {filename}")
    return json.JSONDecoder().raw_decode(source[match.end():])[0]


def name_key(value):
    plain = unicodedata.normalize("NFD", value)
    return re.sub(r"[^a-z0-9]", "", plain.encode("ascii", "ignore").decode().lower())


def project(lon, lat):
    return (lon + 180) / 360, (90 - lat) / 180


def inside_ring(point, ring):
    x, y = point
    hit = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (a[1] > y) != (b[1] > y):
            edge_x = (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
            if x < edge_x:
                hit = not hit
    return hit


def inside_polygon(point, polygon):
    rings = polygon["rings"]
    return inside_ring(point, rings[0]) and not any(inside_ring(point, hole) for hole in rings[1:])


class MapDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.countries = read_assignment("locationData.js", "countries")
        cls.cities = read_assignment("locationData.js", "cities")
        cls.fallback_cities = read_assignment("locationData.js", "fallbackCities")
        cls.states = read_assignment("locationData.js", "states")
        cls.geometry = read_assignment("mapData.js", "countries")

    def test_official_city_coordinates_and_regions(self):
        # Protect against reverting to similarly named or approximate populated-place points.
        expected = {
            "Miami": (-80.1938889, 25.7738889, "Florida"),
            "Chicago": (-87.65, 41.85, "Illinois"),
            "New_York": (-74.0063889, 40.7141667, "New York"),
            "San_Francisco": (-122.4660005, 37.7698135, "California"),
        }
        us = {p["city"]: p for p in self.cities if p["countryCode"] == "US"}
        for city, (lon, lat, region) in expected.items():
            with self.subTest(city=city):
                record = us[city]
                self.assertAlmostEqual(record["lon"], lon, places=7)
                self.assertAlmostEqual(record["lat"], lat, places=7)
                self.assertEqual(record["region"], region)
                self.assertEqual(record["source"], "nordvpn")

    def test_city_records_are_valid_and_unambiguous(self):
        seen = set()
        self.assertGreater(len(self.cities), 200)
        for city in self.cities:
            with self.subTest(country=city["country"], city=city["city"]):
                pair = (name_key(city["country"]), name_key(city["city"]))
                self.assertTrue(all(pair))
                self.assertNotIn(pair, seen)
                seen.add(pair)
                self.assertEqual(city["source"], "nordvpn")
                self.assertTrue(math.isfinite(city["lon"]) and -180 <= city["lon"] <= 180)
                self.assertTrue(math.isfinite(city["lat"]) and -90 <= city["lat"] <= 90)
                self.assertTrue(city["label"])

    def test_fallback_coordinates_remain_identified(self):
        # Raw geographic data may have duplicate city names. It must never be labelled official.
        self.assertGreater(len(self.fallback_cities), 1000)
        for city in self.fallback_cities:
            self.assertEqual(city["source"], "natural-earth")
            self.assertTrue(math.isfinite(city["lon"]) and -180 <= city["lon"] <= 180)
            self.assertTrue(math.isfinite(city["lat"]) and -90 <= city["lat"] <= 90)

    def test_country_anchors_lie_inside_their_country(self):
        # Natural Earth IDs distinguish territory geometries that share an ISO code.
        self.assertGreater(len(self.countries), 230)
        for country in self.countries:
            with self.subTest(country=country["name"], code=country["code"]):
                point = project(country["lon"], country["lat"])
                matching_polygons = [
                    polygon
                    for item in self.geometry if item["id"] == country["id"]
                    for polygon in item["polygons"]
                ]
                self.assertTrue(matching_polygons, "Country anchor has no matching land component")
                self.assertTrue(any(all(abs(a - b) <= EPSILON for a, b in zip(p["bounds"], country["bounds"]))
                                    for p in matching_polygons), "Country focus bounds have no matching land component")
                self.assertTrue(any(inside_polygon(point, p) for p in matching_polygons),
                                "Country anchor is offshore or inside another component's bounds")
                self.assertIn(country["anchorSource"], ("label", "interior"))

    def test_country_ids_and_official_names_are_unambiguous(self):
        ids = [item["id"] for item in self.geometry]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), {item["id"] for item in self.countries})
        official = [item for item in self.countries if item["official"]]
        codes = [item["code"] for item in official]
        names = [name_key(item["name"]) for item in official]
        self.assertEqual(len(codes), len(set(codes)))
        self.assertEqual(len(names), len(set(names)))

    def test_us_country_anchor_is_interior_and_separate_from_city_points(self):
        country = next(p for p in self.countries if p["code"] == "US" and p["official"])
        self.assertTrue(-102 < country["lon"] < -95)
        self.assertTrue(36 < country["lat"] < 43)
        for city in (p for p in self.cities if p["countryCode"] == "US"):
            self.assertGreater(math.hypot(country["lon"] - city["lon"], country["lat"] - city["lat"]), 0.1)

    def test_new_zealand_offshore_label_was_replaced(self):
        country = next(p for p in self.countries if p["code"] == "NZ" and p["official"])
        self.assertEqual(country["anchorSource"], "interior")
        self.assertNotEqual((country["lon"], country["lat"]), (172.787, -39.759))

    def test_geometry_bounds_rings_and_dateline(self):
        for item in self.geometry + self.states:
            for polygon in item["polygons"]:
                bounds = polygon["bounds"]
                self.assertEqual(len(bounds), 4)
                self.assertTrue(all(math.isfinite(v) and 0 <= v <= 1 for v in bounds))
                self.assertLess(bounds[0], bounds[2])
                self.assertLess(bounds[1], bounds[3])
                for detail in ("rings", "overview"):
                    self.assertEqual(len(polygon[detail]), len(polygon["rings"]))
                    for ring in polygon[detail]:
                        self.assertGreaterEqual(len(ring), 4)
                        self.assertEqual(ring[0], ring[-1])
                        for point in ring:
                            self.assertEqual(len(point), 2)
                            x, y = point
                            self.assertTrue(math.isfinite(x) and math.isfinite(y))
                            self.assertTrue(bounds[0] - EPSILON <= x <= bounds[2] + EPSILON)
                            self.assertTrue(bounds[1] - EPSILON <= y <= bounds[3] + EPSILON)
                        for a, b in zip(ring, ring[1:]):
                            # Antarctica's bottom closure may span the world at the pole.
                            polar_closure = a[1] > 0.995 and b[1] > 0.995
                            self.assertTrue(abs(a[0] - b[0]) <= 0.5 or polar_closure,
                                            "Ring draws an antimeridian diagonal across the map")

    def test_zoom_detail_preserves_florida_coastline(self):
        us = next(p for p in self.geometry if p["code"] == "US")
        coast_vertices = 0
        for polygon in us["polygons"]:
            for x, y in polygon["rings"][0]:
                lon, lat = x * 360 - 180, 90 - y * 180
                coast_vertices += -83 <= lon <= -80 and 25 <= lat <= 30
        self.assertGreater(coast_vertices, 100, "Florida detail reverted to a coarse world outline")
        self.assertEqual({p["code"] for p in self.states}, {
            "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN",
            "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
            "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT",
            "VT", "VA", "WA", "WV", "WI", "WY",
        })


if __name__ == "__main__":
    unittest.main()
