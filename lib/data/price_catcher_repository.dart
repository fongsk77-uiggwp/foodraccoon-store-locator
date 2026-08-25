import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/location_area.dart';
import '../models/store.dart';

class PriceCatcherSnapshot {
  const PriceCatcherSnapshot({
    required this.stores,
    required this.dataAsOf,
    required this.sourceMode,
    required this.recommendedBasketCodes,
    required this.locationAreas,
  });

  final List<Store> stores;
  final String dataAsOf;
  final String sourceMode;
  final List<int> recommendedBasketCodes;
  final List<LocationArea> locationAreas;
}

class PriceCatcherRepository {
  static const _excludedPremiseTypePrefixes = <String>['restoran'];
  static const _excludedPremiseTypes = <String>{'foodcourt', 'medan selera'};

  Future<PriceCatcherSnapshot> loadSnapshot() async {
    final raw = await rootBundle.loadString(
      'assets/data/pricecatcher_demo_snapshot.json',
    );
    final document = jsonDecode(raw) as Map<String, dynamic>;
    final metadata = document['metadata'] as Map<String, dynamic>;
    final premiseRows = (document['premises'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final itemRows = (document['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final transactionRows = (document['transactions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final locationRows =
        (document['location_areas'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();

    final itemsByCode = <int, Map<String, dynamic>>{
      for (final item in itemRows) _asInt(item['item_code']): item,
    };
    final transactionsByPremise = <int, List<Map<String, dynamic>>>{};
    for (final transaction in transactionRows) {
      final premiseCode = _asInt(transaction['premise_code']);
      transactionsByPremise.putIfAbsent(premiseCode, () => []).add(transaction);
    }

    final stores = premiseRows
        .where(
          (premise) => !_isExcludedPremiseType(
            premise['premise_type']?.toString() ?? '',
          ),
        )
        .map((premise) {
          final premiseCode = _asInt(premise['premise_code']);
          final products = (transactionsByPremise[premiseCode] ?? []).map((
            row,
          ) {
            final item = itemsByCode[_asInt(row['item_code'])];
            if (item == null) {
              throw StateError('Missing item lookup for ${row['item_code']}');
            }
            return StoreProduct(
              itemCode: _asInt(row['item_code']),
              name: item['item'] as String,
              unit: item['unit'] as String,
              category: item['item_category'] as String,
              price: _asDouble(row['price']),
              date: row['date'] as String,
            );
          }).toList();

          return Store(
            premiseCode: premiseCode,
            name: premise['premise'] as String,
            address: premise['address'] as String,
            type: premise['premise_type'] as String,
            state: premise['state'] as String,
            district: premise['district'] as String,
            city: premise['city']?.toString() ?? '',
            postcode: premise['postcode']?.toString() ?? '',
            latitude: _asDouble(premise['latitude']),
            longitude: _asDouble(premise['longitude']),
            coordinateSource: premise['coordinate_source'] as String,
            openingHours: premise['opening_hours'] as String,
            status: premise['status'] as String,
            products: products,
          );
        })
        .toList();

    final locationAreas = locationRows
        .map(
          (row) => LocationArea(
            city: row['city']?.toString() ?? '',
            state: row['state']?.toString() ?? '',
            postcode: row['postcode']?.toString() ?? '',
            latitude: _asDouble(row['latitude']),
            longitude: _asDouble(row['longitude']),
          ),
        )
        .toList(growable: false);

    return PriceCatcherSnapshot(
      stores: stores,
      dataAsOf: metadata['data_as_of'] as String,
      sourceMode: metadata['source_mode'] as String,
      recommendedBasketCodes: (metadata['recommended_basket_codes'] as List)
          .map(_asInt)
          .toList(),
      locationAreas: locationAreas,
    );
  }

  int _asInt(Object? value) => int.parse(value.toString());

  double _asDouble(Object? value) => double.parse(value.toString());

  bool _isExcludedPremiseType(String value) {
    final type = value.trim().toLowerCase();
    return _excludedPremiseTypes.contains(type) ||
        _excludedPremiseTypePrefixes.any(type.startsWith);
  }
}
