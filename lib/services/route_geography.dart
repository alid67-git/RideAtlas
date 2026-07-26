import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import 'geo_lookup.dart';

const _distance = Distance();

class CountryLeg {
  const CountryLeg({
    required this.country,
    required this.countryCode,
    required this.distanceKm,
    required this.duration,
    required this.cities,
  });

  final String country;
  final String? countryCode;
  final double distanceKm;
  final Duration? duration;
  final List<String> cities;
}

class DetectedStop {
  const DetectedStop({
    required this.location,
    required this.start,
    required this.end,
    required this.duration,
    this.country,
    this.city,
  });

  final LatLng location;
  final DateTime? start;
  final DateTime? end;
  final Duration duration;
  final String? country;
  final String? city;
}

class RouteGeography {
  const RouteGeography({
    required this.legs,
    required this.stops,
    required this.uniqueCountries,
  });

  final List<CountryLeg> legs;
  final List<DetectedStop> stops;
  final List<String> uniqueCountries;
}

typedef GeographyProgress = void Function(String message, double? progress);

/// Builds country legs (sampled along the track) and detects dwell stops.
class RouteGeographyAnalyzer {
  RouteGeographyAnalyzer({GeoLookup? geo}) : _geo = geo ?? GeoLookup.instance;

  final GeoLookup _geo;

  /// Sample roughly every [sampleEveryKm] and reverse-geocode; merge into
  /// ordered country legs with distance / duration / cities.
  Future<RouteGeography> analyze(
    List<TrackPoint> points, {
    double sampleEveryKm = 30,
    Duration minStop = const Duration(minutes: 20),
    double stopRadiusMeters = 180,
    GeographyProgress? onProgress,
  }) async {
    onProgress?.call('Molalar hesaplanıyor…', 0.05);
    final rawStops = detectStops(
      points,
      minDuration: minStop,
      radiusMeters: stopRadiusMeters,
    );

    onProgress?.call('Güzergâh örnekleniyor…', 0.1);
    final samples = _sampleAlongTrack(points, sampleEveryKm);
    // Always include stop centroids so city names enrich legs / stop cards.
    final lookupPoints = <LatLng>[
      ...samples.map((s) => s.latLng),
      ...rawStops.map((s) => s.location),
    ];

    final places = <String, PlaceInfo?>{};
    for (var i = 0; i < lookupPoints.length; i++) {
      final ll = lookupPoints[i];
      final key = GeoLookup.cacheKey(ll);
      if (places.containsKey(key)) continue;
      onProgress?.call(
        'Konum çözülüyor (${i + 1}/${lookupPoints.length})…',
        0.1 + 0.75 * ((i + 1) / lookupPoints.length),
      );
      places[key] = await _geo.lookup(ll);
    }

    final legs = _buildCountryLegs(points, samples, places);
    final stops = [
      for (final s in rawStops)
        DetectedStop(
          location: s.location,
          start: s.start,
          end: s.end,
          duration: s.duration,
          country: places[GeoLookup.cacheKey(s.location)]?.country,
          city: places[GeoLookup.cacheKey(s.location)]?.city,
        ),
    ]..sort((a, b) {
      final aT = a.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bT = b.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aT.compareTo(bT);
    });

    final unique = <String>[];
    for (final leg in legs) {
      if (!unique.contains(leg.country)) unique.add(leg.country);
    }

    onProgress?.call('Tamam', 1);
    return RouteGeography(legs: legs, stops: stops, uniqueCountries: unique);
  }

  /// Dwell clusters: stay within [radiusMeters] for at least [minDuration].
  List<DetectedStop> detectStops(
    List<TrackPoint> points, {
    Duration minDuration = const Duration(minutes: 20),
    double radiusMeters = 180,
  }) {
    final stops = <DetectedStop>[];
    if (points.length < 2) return stops;

    var clusterStart = 0;
    var sumLat = points.first.latLng.latitude;
    var sumLon = points.first.latLng.longitude;
    var count = 1;

    void flush(int endExclusive) {
      if (endExclusive - clusterStart < 2) return;
      final startPt = points[clusterStart];
      final endPt = points[endExclusive - 1];
      final t0 = startPt.time;
      final t1 = endPt.time;
      Duration? dur;
      if (t0 != null && t1 != null && !t1.isBefore(t0)) {
        dur = t1.difference(t0);
      }
      if (dur == null || dur < minDuration) return;
      stops.add(
        DetectedStop(
          location: LatLng(sumLat / count, sumLon / count),
          start: t0,
          end: t1,
          duration: dur,
        ),
      );
    }

    for (var i = 1; i < points.length; i++) {
      final center = LatLng(sumLat / count, sumLon / count);
      final d = _distance(center, points[i].latLng);
      if (d <= radiusMeters) {
        sumLat += points[i].latLng.latitude;
        sumLon += points[i].latLng.longitude;
        count++;
      } else {
        flush(i);
        clusterStart = i;
        sumLat = points[i].latLng.latitude;
        sumLon = points[i].latLng.longitude;
        count = 1;
      }
    }
    flush(points.length);
    return stops;
  }

  List<_Sample> _sampleAlongTrack(List<TrackPoint> points, double everyKm) {
    final out = <_Sample>[];
    if (points.isEmpty) return out;

    out.add(_Sample(0, 0, points.first));
    var cumulativeKm = 0.0;
    var nextAt = everyKm;
    for (var i = 1; i < points.length; i++) {
      cumulativeKm +=
          _distance(points[i - 1].latLng, points[i].latLng) / 1000.0;
      if (cumulativeKm >= nextAt) {
        out.add(_Sample(i, cumulativeKm, points[i]));
        nextAt += everyKm;
      }
    }
    final last = points.last;
    if (out.last.index != points.length - 1) {
      out.add(_Sample(points.length - 1, cumulativeKm, last));
    }
    return out;
  }

  List<CountryLeg> _buildCountryLegs(
    List<TrackPoint> points,
    List<_Sample> samples,
    Map<String, PlaceInfo?> places,
  ) {
    if (samples.isEmpty) return const [];

    PlaceInfo? placeAt(_Sample s) => places[GeoLookup.cacheKey(s.latLng)];

    final legs = <CountryLeg>[];
    String? currentCountry;
    String? currentCode;
    final cities = <String>{};
    var legStartKm = 0.0;
    DateTime? legStartTime = samples.first.point.time;
    var lastKm = 0.0;
    DateTime? lastTime = samples.first.point.time;

    void flush(double endKm, DateTime? endTime) {
      if (currentCountry == null) return;
      Duration? dur;
      if (legStartTime != null && endTime != null && !endTime.isBefore(legStartTime)) {
        dur = endTime.difference(legStartTime);
      }
      legs.add(
        CountryLeg(
          country: currentCountry!,
          countryCode: currentCode,
          distanceKm: (endKm - legStartKm).clamp(0, double.infinity),
          duration: dur,
          cities: cities.toList()..sort(),
        ),
      );
      cities.clear();
    }

    for (final s in samples) {
      final place = placeAt(s);
      final country = place?.country;
      final city = place?.city;
      if (city != null &&
          currentCountry != null &&
          country == currentCountry) {
        cities.add(city);
      }

      if (country == null) {
        lastKm = s.distanceKm;
        lastTime = s.point.time ?? lastTime;
        continue;
      }

      if (currentCountry == null) {
        currentCountry = country;
        currentCode = place?.countryCode;
        legStartKm = s.distanceKm;
        legStartTime = s.point.time;
        if (city != null) cities.add(city);
      } else if (country != currentCountry) {
        flush(s.distanceKm, s.point.time ?? lastTime);
        currentCountry = country;
        currentCode = place?.countryCode;
        legStartKm = s.distanceKm;
        legStartTime = s.point.time ?? lastTime;
        if (city != null) cities.add(city);
      }

      lastKm = s.distanceKm;
      lastTime = s.point.time ?? lastTime;
    }

    flush(lastKm, lastTime);

    // Prefer full track distance for a single-country tour.
    if (legs.length == 1 && points.length >= 2) {
      var total = 0.0;
      for (var i = 1; i < points.length; i++) {
        total += _distance(points[i - 1].latLng, points[i].latLng) / 1000.0;
      }
      final only = legs.first;
      return [
        CountryLeg(
          country: only.country,
          countryCode: only.countryCode,
          distanceKm: total,
          duration: only.duration,
          cities: only.cities,
        ),
      ];
    }

    return legs;
  }
}

class _Sample {
  _Sample(this.index, this.distanceKm, this.point);
  final int index;
  final double distanceKm;
  final TrackPoint point;
  LatLng get latLng => point.latLng;
}
