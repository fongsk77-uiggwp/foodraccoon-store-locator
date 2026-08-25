# FoodRaccoon Store Locator

The first Flutter version of the FoodRaccoon Store Locator module for BMIT2073 Mobile Application Development.

## Included flow

- Nearby stores on an OpenStreetMap map
- Mobile map with the five nearest stores below it and a Show more toggle
- Distance-sorted store list
- Search and premise-type filters
- Homepage type-ahead search with up to three store suggestions for a name or area
- Filter panel store labels: Supermarket, Hypermarket, Fresh Market, Grocery Shop, and Mini Market
- Filter and sort sheet with nearest, name, price-data, open-now, and price-availability options
- Device GPS, tap-anywhere map pinning, and manual place selection
- Separate location picker with GPS, map pinning, postcode-based area suggestions, and manual address input
- Store search uses PriceCatcher premise names, addresses, cities, and postcodes; the location picker never suggests stores
- Best-value basket calculation
- Store details, price availability summaries, and latest recorded prices
- View prices and open a Google Maps route from every store card
- Tap the Distance metric in store details to open the same Google Maps route
- Clear no-price-data and approximate-location labels
- Route handoff to Google Maps
- Current-location support with a Setapak fallback

## PriceCatcher data

The bundled asset is a nationwide snapshot from Malaysia's official PriceCatcher files as of 21 August 2026. It covers 2,951 grocery-related premises, including 2,124 premises with current transaction records, 289 items, and 190,936 latest premise-item prices across all Malaysian states and federal territories. Restaurant, foodcourt, and medan selera premises are excluded because this module focuses on grocery store discovery:

- Transactional Records: https://storage.data.gov.my/pricecatcher/pricecatcher_2026-08.csv
- Item Lookup: https://storage.data.gov.my/pricecatcher/lookup_item.csv
- Premise Lookup: https://storage.data.gov.my/pricecatcher/lookup_premise.csv
- Malaysia Postcode Dataset: https://storage.data.gov.my/dictionaries/postcodes.csv

Transactions are joined to premises through `premise_code` and to products through `item_code`. The snapshot keeps the latest available August record for each premise-item pair while retaining premises with no current transaction, so the UI can distinguish a real store from a store with no recent price data. The official postcode dataset is joined by address postcode to enrich city and postcode display and generate 397 unique area suggestions for the location picker, including Puchong, Selangor. The official premise lookup provides addresses but not coordinates, so the generator uses GeoNames Malaysia postcode centroids for map placement, with a state-centre fallback when an address has no matching postcode. Opening hours are derived metadata used for the Store Locator interface; the displayed open-status is calculated dynamically from those hours using Malaysia time.

The postcode coordinate supplement is licensed under CC BY 4.0 and is credited to [GeoNames](https://www.geonames.org/). It is used only during offline asset generation; the mobile app does not bulk-geocode addresses at runtime.

The snapshot can be regenerated with `tooling/generate_selected_pricecatcher_snapshot.py` after placing the four official CSV files and `geonames_my/MY.txt` in `../tmp_pricecatcher_raw`.

## Flutter packages

- `flutter_map`
- `latlong2`
- `geolocator`
- `geocoding`
- `url_launcher`

## Run

```text
flutter pub get
flutter run
```
