import csv
import json
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT.parent / "tmp_pricecatcher_raw"
OUTPUT = ROOT / "assets" / "data" / "pricecatcher_demo_snapshot.json"

GEONAMES_POSTCODES = RAW / "geonames_my" / "MY.txt"
OFFICIAL_POSTCODES = RAW / "postcodes.csv"

EXCLUDED_PREMISE_TYPES = {"foodcourt", "medan selera"}

STATE_CENTRES = {
    "Johor": (2.0000, 103.3500),
    "Kedah": (6.1200, 100.3700),
    "Kelantan": (6.1300, 102.2400),
    "Melaka": (2.1900, 102.2500),
    "Negeri Sembilan": (2.7300, 101.9400),
    "Pahang": (3.8100, 103.3300),
    "Perak": (4.6000, 101.0700),
    "Perlis": (6.4500, 100.2500),
    "Pulau Pinang": (5.4100, 100.3300),
    "Sabah": (5.9800, 116.0700),
    "Sarawak": (1.5500, 110.3500),
    "Selangor": (3.0700, 101.5200),
    "Terengganu": (5.3300, 103.1400),
    "W.P. Kuala Lumpur": (3.1400, 101.6900),
    "W.P. Labuan": (5.2800, 115.2400),
    "W.P. Putrajaya": (2.9300, 101.6900),
}


def code(value):
    return int(float(value))


def clean(value):
    return (value or "").strip()


def is_excluded_premise_type(value):
    premise_type = clean(value).casefold()
    return premise_type.startswith("restoran") or premise_type in EXCLUDED_PREMISE_TYPES


def load_lookups():
    premises = {}
    with (RAW / "lookup_premise.csv").open(
        encoding="utf-8-sig", newline=""
    ) as file:
        for row in csv.DictReader(file):
            if not row["premise_code"] or float(row["premise_code"]) < 0:
                continue
            if not row["state"] or not row["district"]:
                continue
            if is_excluded_premise_type(row["premise_type"]):
                continue
            premises[code(row["premise_code"])] = row

    items = {}
    with (RAW / "lookup_item.csv").open(encoding="utf-8-sig", newline="") as file:
        for row in csv.DictReader(file):
            if not row["item_code"] or float(row["item_code"]) < 0:
                continue
            items[code(row["item_code"])] = row
    return premises, items


def load_official_postcodes():
    postcodes = defaultdict(list)
    with OFFICIAL_POSTCODES.open(encoding="utf-8-sig", newline="") as file:
        for row in csv.DictReader(file):
            postcode = clean(row["postcode"])
            if not re.fullmatch(r"\d{5}", postcode):
                continue
            postcodes[postcode].append(
                {
                    "city": clean(row["city"]),
                    "state": clean(row["state"]),
                }
            )
    return postcodes


def load_postcode_coordinates():
    coordinates = defaultdict(list)
    with GEONAMES_POSTCODES.open(encoding="utf-8", newline="") as file:
        for line in file:
            columns = line.rstrip("\n").split("\t")
            if len(columns) < 11 or columns[0] != "MY":
                continue
            try:
                coordinates[columns[1]].append(
                    (columns[2].lower(), float(columns[9]), float(columns[10]))
                )
            except ValueError:
                continue
    return coordinates


def load_location_areas(official_postcodes, postcode_coordinates):
    grouped = {}
    for postcode, candidates in official_postcodes.items():
        coordinate_candidates = postcode_coordinates.get(postcode, [])
        for candidate in candidates:
            city = clean(candidate["city"])
            state = clean(candidate["state"])
            if not city or not state:
                continue

            city_key = city.casefold()
            matching_coordinate = next(
                (
                    coordinate
                    for coordinate in coordinate_candidates
                    if coordinate[0] and city_key in coordinate[0].casefold()
                ),
                coordinate_candidates[0] if coordinate_candidates else None,
            )
            if matching_coordinate is not None:
                latitude, longitude = matching_coordinate[1], matching_coordinate[2]
            else:
                latitude, longitude = STATE_CENTRES.get(
                    state, STATE_CENTRES["W.P. Kuala Lumpur"]
                )

            key = (city_key, state.casefold())
            area = grouped.setdefault(
                key,
                {
                    "city": city,
                    "state": state,
                    "postcodes": [],
                    "latitudes": [],
                    "longitudes": [],
                },
            )
            area["postcodes"].append(postcode)
            area["latitudes"].append(latitude)
            area["longitudes"].append(longitude)

    location_areas = []
    for area in grouped.values():
        location_areas.append(
            {
                "city": area["city"],
                "state": area["state"],
                "postcode": sorted(set(area["postcodes"]))[0],
                "latitude": round(
                    sum(area["latitudes"]) / len(area["latitudes"]), 6
                ),
                "longitude": round(
                    sum(area["longitudes"]) / len(area["longitudes"]), 6
                ),
            }
        )
    return sorted(
        location_areas,
        key=lambda area: (area["city"].casefold(), area["state"].casefold()),
    )


def address_postcode_and_city(row, official_postcodes):
    match = re.search(r"\b(\d{5})\b", clean(row["address"]))
    if not match or match.group(1) not in official_postcodes:
        return "", ""

    postcode = match.group(1)
    address = clean(row["address"]).casefold()
    candidates = official_postcodes[postcode]
    matching_city = next(
        (
            candidate["city"]
            for candidate in candidates
            if candidate["city"] and candidate["city"].casefold() in address
        ),
        candidates[0]["city"],
    )
    return postcode, matching_city


def load_latest_transactions(premise_codes, item_codes):
    latest = {}
    with (RAW / "pricecatcher_2026-08.csv").open(
        encoding="utf-8-sig", newline=""
    ) as file:
        for row in csv.DictReader(file):
            premise_code = code(row["premise_code"])
            item_code = code(row["item_code"])
            key = (premise_code, item_code)
            if premise_code not in premise_codes or item_code not in item_codes:
                continue
            previous = latest.get(key)
            if previous is None or row["date"] >= previous["date"]:
                latest[key] = row
    return latest


def derived_location(row, postcode_coordinates):
    match = re.search(r"\b(\d{5})\b", clean(row["address"]))
    if match and match.group(1) in postcode_coordinates:
        address = clean(row["address"]).lower()
        candidates = postcode_coordinates[match.group(1)]
        matching_place = next(
            (candidate for candidate in candidates if candidate[0] and candidate[0] in address),
            None,
        )
        place, latitude, longitude = matching_place or candidates[0]
        return round(latitude, 6), round(longitude, 6), "postcode centroid"

    latitude, longitude = STATE_CENTRES.get(
        clean(row["state"]), STATE_CENTRES["W.P. Kuala Lumpur"]
    )
    return latitude, longitude, "state centre fallback"


def build_document():
    premises, items = load_lookups()
    postcode_coordinates = load_postcode_coordinates()
    official_postcodes = load_official_postcodes()
    location_areas = load_location_areas(official_postcodes, postcode_coordinates)
    latest = load_latest_transactions(set(premises), set(items))
    transactions_by_premise = defaultdict(list)
    item_codes = set()
    for row in latest.values():
        premise_code = code(row["premise_code"])
        item_code = code(row["item_code"])
        transactions_by_premise[premise_code].append(
            {
                "date": row["date"],
                "premise_code": premise_code,
                "item_code": item_code,
                "price": float(row["price"]),
            }
        )
        item_codes.add(item_code)

    premise_rows = []
    # Keep every premise from the official Premise Lookup, including stores
    # without a transaction in the selected month. This lets the UI explain
    # the difference between a real store and missing current price data.
    selected_premise_codes = sorted(premises)
    coordinate_sources = defaultdict(int)
    official_postcode_matches = 0
    for premise_code in selected_premise_codes:
        row = premises[premise_code]
        latitude, longitude, coordinate_source = derived_location(
            row, postcode_coordinates
        )
        postcode, city = address_postcode_and_city(row, official_postcodes)
        if postcode:
            official_postcode_matches += 1
        coordinate_sources[coordinate_source] += 1
        premise_rows.append(
            {
                "premise_code": premise_code,
                "premise": clean(row["premise"]),
                "address": clean(row["address"]),
                "premise_type": clean(row["premise_type"]),
                "state": clean(row["state"]),
                "district": clean(row["district"]),
                "city": city,
                "postcode": postcode,
                "latitude": latitude,
                "longitude": longitude,
                "coordinate_source": coordinate_source,
                "opening_hours": "08:00–22:00",
                "status": "Open now",
            }
        )

    item_rows = []
    for item_code in sorted(item_codes):
        row = items[item_code]
        item_rows.append(
            {
                "item_code": item_code,
                "item": clean(row["item"]),
                "unit": clean(row["unit"]),
                "item_group": clean(row["item_group"]),
                "item_category": clean(row["item_category"]),
            }
        )

    transactions = sorted(
        (transaction for rows in transactions_by_premise.values() for transaction in rows),
        key=lambda row: (row["premise_code"], row["item_code"]),
    )
    metadata = {
        "data_as_of": "2026-08-21",
        "source_mode": "nationwide official PriceCatcher snapshot with official postcode enrichment",
        "selected_state": "All Malaysia",
        "selected_districts": "All districts in the official Premise Lookup",
        "recommended_basket_codes": [1109, 92, 113],
        "transactional_records_url": "https://storage.data.gov.my/pricecatcher/pricecatcher_2026-08.csv",
        "item_lookup_url": "https://storage.data.gov.my/pricecatcher/lookup_item.csv",
        "premise_lookup_url": "https://storage.data.gov.my/pricecatcher/lookup_premise.csv",
        "postcode_lookup_url": "https://storage.data.gov.my/dictionaries/postcodes.csv",
        "location_area_count": len(location_areas),
        "location_area_source_url": "https://storage.data.gov.my/dictionaries/postcodes.csv",
        "coordinate_source": dict(coordinate_sources),
        "official_postcode_matches": official_postcode_matches,
        "excluded_premise_types": ["Restoran*", "Foodcourt", "Medan Selera"],
        "notes": "Premises are nationwide grocery-related records from the official PriceCatcher Premise Lookup; restaurant, foodcourt, and medan selera premises are excluded. Prices and items come from the selected monthly official PriceCatcher files; stores without a current transaction remain visible with a no-price-data status. Official Malaysia postcode data enriches city and postcode display and provides area-only location suggestions. Coordinates use GeoNames Malaysia postal-code centroids when an address contains a matching postcode, with state-centre fallback otherwise. Opening hours and open-status fields are derived demonstration metadata for the Store Locator UI.",
        "coordinate_source_url": "https://download.geonames.org/export/zip/MY.zip",
    }
    return {
        "metadata": metadata,
        "premises": premise_rows,
        "location_areas": location_areas,
        "items": item_rows,
        "transactions": transactions,
    }


if __name__ == "__main__":
    document = build_document()
    OUTPUT.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Generated {len(document['premises'])} premises, "
        f"{len(document['items'])} items, and "
        f"{len(document['transactions'])} transactions."
    )
