import 'package:latlong2/latlong.dart';

class LocationArea {
  const LocationArea({
    required this.city,
    required this.state,
    required this.postcode,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String state;
  final String postcode;
  final double latitude;
  final double longitude;

  LatLng get location => LatLng(latitude, longitude);

  String get label =>
      [city, state].where((part) => part.trim().isNotEmpty).join(', ');

  String get subtitle =>
      postcode.trim().isEmpty ? 'Location area' : 'Location area • $postcode';
}
