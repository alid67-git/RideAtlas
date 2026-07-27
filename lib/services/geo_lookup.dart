import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Reverse-geocoded place (country / city), cached in Hive so long tours
/// don't re-hit the network every time the analysis sheet opens.
class PlaceInfo {
  const PlaceInfo({
    this.country,
    this.countryCode,
    this.city,
  });

  final String? country;
  final String? countryCode;
  final String? city;

  bool get hasCountry => country != null && country!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'country': country,
    'countryCode': countryCode,
    'city': city,
  };

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
    country: json['country'] as String?,
    countryCode: json['countryCode'] as String?,
    city: json['city'] as String?,
  );
}

const _boxName = 'rideatlas_geo_cache';

/// BigDataCloud reverse-geocode (no API key, browser-friendly CORS).
class GeoLookup {
  GeoLookup._();
  static final GeoLookup instance = GeoLookup._();

  Box<String>? _box;
  Future<Box<String>>? _inflightOpen;
  DateTime? _lastRequestAt;

  Future<Box<String>> _open() async {
    if (_box != null) return _box!;
    return _inflightOpen ??= Hive.openBox<String>(_boxName).then((b) {
      _box = b;
      return b;
    });
  }

  /// ~5–6 km grid cell — good enough for country / city labels on a tour.
  static String cacheKey(LatLng ll) {
    final lat = (ll.latitude * 20).round();
    final lon = (ll.longitude * 20).round();
    return 'g_${lat}_$lon';
  }

  Future<PlaceInfo?> lookup(LatLng ll) async {
    final box = await _open();
    final key = cacheKey(ll);
    final cached = box.get(key);
    if (cached != null) {
      try {
        return PlaceInfo.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {
        await box.delete(key);
      }
    }

    await _throttle();
    final uri = Uri.https(
      'api.bigdatacloud.net',
      '/data/reverse-geocode-client',
      {
        'latitude': ll.latitude.toStringAsFixed(5),
        'longitude': ll.longitude.toStringAsFixed(5),
        'localityLanguage': 'tr',
      },
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final city = _firstNonEmpty([
        json['city'] as String?,
        json['locality'] as String?,
        json['principalSubdivision'] as String?,
      ]);
      final place = PlaceInfo(
        country: _emptyToNull(json['countryName'] as String?),
        countryCode: _emptyToNull(json['countryCode'] as String?),
        city: city,
      );
      await box.put(key, jsonEncode(place.toJson()));
      return place;
    } catch (_) {
      return null;
    }
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final wait = const Duration(milliseconds: 220) - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();
  }

  static String? _emptyToNull(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }
}
