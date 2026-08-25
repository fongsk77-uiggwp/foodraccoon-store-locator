import 'package:latlong2/latlong.dart';

class StoreProduct {
  const StoreProduct({
    required this.itemCode,
    required this.name,
    required this.unit,
    required this.category,
    required this.price,
    required this.date,
  });

  final int itemCode;
  final String name;
  final String unit;
  final String category;
  final double price;
  final String date;
}

class Store {
  const Store({
    required this.premiseCode,
    required this.name,
    required this.address,
    required this.type,
    required this.state,
    required this.district,
    required this.city,
    required this.postcode,
    required this.latitude,
    required this.longitude,
    required this.coordinateSource,
    required this.openingHours,
    required this.status,
    required this.products,
  });

  final int premiseCode;
  final String name;
  final String address;
  final String type;
  final String state;
  final String district;
  final String city;
  final String postcode;
  final double latitude;
  final double longitude;
  final String coordinateSource;
  final String openingHours;
  final String status;
  final List<StoreProduct> products;

  String get locality =>
      [city, postcode].where((part) => part.trim().isNotEmpty).join(', ');

  LatLng get location => LatLng(latitude, longitude);

  int get productCount => products.length;

  bool get hasPriceData => products.isNotEmpty;

  bool get isOpenNow => isOpenAt(_malaysiaNow());

  String get currentStatus => isOpenNow ? 'Open now' : 'Closed now';

  bool isOpenAt(DateTime time) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})',
    ).firstMatch(openingHours);
    if (match == null) return status == 'Open now';

    final opening =
        int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    final closing =
        int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
    final current = time.hour * 60 + time.minute;

    if (opening == closing) return true;
    if (closing > opening) {
      return current >= opening && current < closing;
    }
    return current >= opening || current < closing;
  }

  DateTime _malaysiaNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  double? get lowestPrice {
    if (products.isEmpty) return null;
    return products
        .map((product) => product.price)
        .reduce((lowest, price) => price < lowest ? price : lowest);
  }

  String? get latestPriceDate {
    if (products.isEmpty) return null;
    return products
        .map((product) => product.date)
        .reduce((latest, date) => date.compareTo(latest) > 0 ? date : latest);
  }

  double? basketTotal(List<int> itemCodes) {
    final selected = <int, StoreProduct>{
      for (final product in products) product.itemCode: product,
    };
    if (itemCodes.any((code) => !selected.containsKey(code))) {
      return null;
    }
    return itemCodes.fold<double>(
      0,
      (total, code) => total + selected[code]!.price,
    );
  }
}
