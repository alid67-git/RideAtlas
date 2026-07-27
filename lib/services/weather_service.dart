import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';

class DayWeather {
  const DayWeather({
    required this.date,
    required this.location,
    required this.weatherCode,
    required this.label,
    required this.tempMaxC,
    required this.tempMinC,
    required this.precipitationMm,
  });

  final DateTime date;
  final LatLng location;
  final int weatherCode;
  final String label;
  final double? tempMaxC;
  final double? tempMinC;
  final double? precipitationMm;

  IconData get icon => weatherCodeIcon(weatherCode);
}

/// Historical daily weather via Open-Meteo Archive (free, no key).
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  Future<List<DayWeather>> forTrack(
    List<TrackPoint> points, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    final byDay = <String, _DayBucket>{};

    for (final p in points) {
      final t = p.time;
      if (t == null) continue;
      final local = t.toLocal();
      final key =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      final bucket = byDay.putIfAbsent(key, () => _DayBucket(key));
      bucket.sumLat += p.latLng.latitude;
      bucket.sumLon += p.latLng.longitude;
      bucket.count++;
    }

    if (byDay.isEmpty) return const [];

    final keys = byDay.keys.toList()..sort();
    final out = <DayWeather>[];

    for (var i = 0; i < keys.length; i++) {
      final bucket = byDay[keys[i]]!;
      onProgress?.call(
        'Hava durumu (${i + 1}/${keys.length})…',
        (i + 1) / keys.length,
      );
      final lat = bucket.sumLat / bucket.count;
      final lon = bucket.sumLon / bucket.count;
      final day = await _fetchDay(lat, lon, bucket.dateKey);
      if (day != null) out.add(day);
    }

    return out;
  }

  Future<DayWeather?> _fetchDay(double lat, double lon, String dateKey) async {
    final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'start_date': dateKey,
      'end_date': dateKey,
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum',
      'timezone': 'auto',
    });

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>?;
      if (daily == null) return null;

      final codes = daily['weather_code'] as List<dynamic>?;
      final tmax = daily['temperature_2m_max'] as List<dynamic>?;
      final tmin = daily['temperature_2m_min'] as List<dynamic>?;
      final precip = daily['precipitation_sum'] as List<dynamic>?;
      if (codes == null || codes.isEmpty) return null;

      final code = (codes.first as num).toInt();
      return DayWeather(
        date: DateTime.parse(dateKey),
        location: LatLng(lat, lon),
        weatherCode: code,
        label: weatherCodeLabelTr(code),
        tempMaxC: tmax == null || tmax.isEmpty
            ? null
            : (tmax.first as num?)?.toDouble(),
        tempMinC: tmin == null || tmin.isEmpty
            ? null
            : (tmin.first as num?)?.toDouble(),
        precipitationMm: precip == null || precip.isEmpty
            ? null
            : (precip.first as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _DayBucket {
  _DayBucket(this.dateKey);
  final String dateKey;
  double sumLat = 0;
  double sumLon = 0;
  int count = 0;
}

String weatherCodeLabelTr(int code) {
  if (code == 0) return 'Açık';
  if (code == 1) return 'Çoğunlukla açık';
  if (code == 2) return 'Parçalı bulutlu';
  if (code == 3) return 'Kapalı';
  if (code == 45 || code == 48) return 'Sis';
  if (code >= 51 && code <= 57) return 'Çisenti';
  if (code >= 61 && code <= 67) return 'Yağmur';
  if (code >= 71 && code <= 77) return 'Kar';
  if (code >= 80 && code <= 82) return 'Sağanak';
  if (code >= 85 && code <= 86) return 'Kar sağanağı';
  if (code >= 95 && code <= 99) return 'Gök gürültülü';
  return 'Değişken';
}

IconData weatherCodeIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.filter_drama;
  if (code == 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.dehaze;
  if (code >= 51 && code <= 67) return Icons.water_drop_outlined;
  if (code >= 71 && code <= 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}
