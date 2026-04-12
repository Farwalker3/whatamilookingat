import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Location service using GPS + OpenStreetMap Nominatim reverse geocoding.
class LocationService {
  Position? _lastPosition;
  Map<String, String>? _lastGeocode;
  DateTime? _lastGeocodeTime;

  Position? get lastPosition => _lastPosition;

  /// Get current position with permission handling.
  Future<Position?> getCurrentPosition() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _lastPosition;

      // Check permissions
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return _lastPosition;
      }
      if (permission == LocationPermission.deniedForever) return _lastPosition;

      _lastPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _lastPosition;
    } catch (_) {
      return _lastPosition;
    }
  }

  /// Reverse geocode coordinates to place name using OSM Nominatim (free, no key).
  Future<Map<String, String>> reverseGeocode(double lat, double lon) async {
    // Cache for 30 seconds
    if (_lastGeocode != null &&
        _lastGeocodeTime != null &&
        DateTime.now().difference(_lastGeocodeTime!).inSeconds < 30) {
      return _lastGeocode!;
    }

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?'
        'format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'WhatAmILookingAt/1.0',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>? ?? {};

        _lastGeocode = {
          'display': data['display_name'] as String? ?? '',
          'place': address['amenity'] as String? ??
              address['building'] as String? ??
              address['shop'] as String? ??
              address['tourism'] as String? ??
              '',
          'street': _buildStreetName(address),
          'city': address['city'] as String? ??
              address['town'] as String? ??
              address['village'] as String? ??
              '',
          'state': address['state'] as String? ?? '',
          'country': address['country'] as String? ?? '',
          'countryCode': address['country_code'] as String? ?? '',
        };
        _lastGeocodeTime = DateTime.now();
        return _lastGeocode!;
      }
    } catch (_) {
      // Geocoding failed, return empty
    }

    return _lastGeocode ?? {};
  }

  String _buildStreetName(Map<String, dynamic> address) {
    final houseNumber = address['house_number'] as String?;
    final road = address['road'] as String?;
    if (road == null) return '';
    if (houseNumber != null) return '$houseNumber $road';
    return road;
  }

  /// Get compass heading (returns null if not available).
  /// Note: Compass heading requires platform-specific sensor access.
  /// For simplicity, we'll derive heading from GPS bearing when moving.
  double? getHeadingFromPosition() {
    return _lastPosition?.heading;
  }
}
