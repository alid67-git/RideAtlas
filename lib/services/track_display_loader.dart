import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/gpx_route.dart';
import '../repositories/route_repository.dart';
import 'track_display_simplify.dart';
import 'track_io.dart';

/// How many track XML→display jobs to run in parallel for "show all".
/// Keep low on purpose: each job holds a full GPX string + parsed points in
/// an isolate; 4× large rides peaked RAM and ANR'd Android (~20 tracks).
const kTrackDisplayLoadConcurrency = 2;

/// Args for [parseXmlForMapDisplayCoords] (must be isolate-sendable).
class MapDisplayParseRequest {
  const MapDisplayParseRequest({
    required this.xml,
    required this.maxPoints,
    required this.minSpacingMeters,
  });

  final String xml;
  final int maxPoints;
  final double minSpacingMeters;
}

/// Isolate entry: parse + filter + simplify, return only display coords.
/// Shipping full GPX point lists across isolates was a major show-all cost.
List<List<double>> parseXmlForMapDisplayCoords(MapDisplayParseRequest req) {
  final parsed = parseAndFilterTrackXml(req.xml);
  final points = latLngsForMapDisplay(
    [for (final p in parsed.points) p.latLng],
    maxPoints: req.maxPoints,
    minSpacingMeters: req.minSpacingMeters,
  );
  return [
    for (final p in points) <double>[p.latitude, p.longitude],
  ];
}

List<LatLng> _coordsToLatLngs(List<List<double>> coords) => [
      for (final c in coords) LatLng(c[0], c[1]),
    ];

/// Process-wide LRU of simplified display polylines so a second "show all"
/// paints immediately instead of re-parsing every GPX.
class TrackDisplayCache {
  TrackDisplayCache._();
  static final TrackDisplayCache instance = TrackDisplayCache._();

  static const _maxEntries = 80;

  final _entries = <String, List<LatLng>>{};
  final _order = <String>[];

  static String key({
    required String routeId,
    required int maxPoints,
    required double minSpacingMeters,
    required int pointCount,
    String? fingerprint,
  }) {
    final fp = fingerprint ?? 'n$pointCount';
    return '$routeId|$maxPoints|${minSpacingMeters.round()}|$fp';
  }

  List<LatLng>? get(String key) {
    final hit = _entries[key];
    if (hit == null) return null;
    _order.remove(key);
    _order.add(key);
    return hit;
  }

  void put(String key, List<LatLng> points) {
    if (_entries.containsKey(key)) {
      _order.remove(key);
    }
    _entries[key] = points;
    _order.add(key);
    while (_order.length > _maxEntries) {
      final evict = _order.removeAt(0);
      _entries.remove(evict);
    }
  }

  void clear() {
    _entries.clear();
    _order.clear();
  }

  @visibleForTesting
  int get length => _entries.length;
}

/// One route ready for a multi-route / overlay map.
class LoadedDisplayTrack {
  const LoadedDisplayTrack({
    required this.route,
    required this.points,
    required this.index,
  });

  final GpxRoute route;
  final List<LatLng> points;
  final int index;
}

/// Reads + parses routes in parallel (bounded), using [TrackDisplayCache].
///
/// Returns tracks in input order. Callers should paint **once** with the
/// full list — progressive per-route setState was both slow and memory-heavy.
Future<List<LoadedDisplayTrack>> loadTracksForMapDisplay({
  required RouteRepository repo,
  required List<GpxRoute> routes,
  required int maxPoints,
  required double minSpacingMeters,
  void Function(int loaded, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (routes.isEmpty) return const [];

  final total = routes.length;
  final slots = List<LoadedDisplayTrack?>.filled(total, null);
  var completed = 0;

  void bumpProgress() {
    completed++;
    onProgress?.call(completed, total);
  }

  // Serve cache hits synchronously so a second "show all" paints fast.
  final missIndexes = <int>[];
  for (var i = 0; i < routes.length; i++) {
    final route = routes[i];
    final cacheKey = TrackDisplayCache.key(
      routeId: route.id,
      maxPoints: maxPoints,
      minSpacingMeters: minSpacingMeters,
      pointCount: route.pointCount,
      fingerprint: route.trackFingerprint,
    );
    final cached = TrackDisplayCache.instance.get(cacheKey);
    if (cached != null && cached.length >= 2) {
      slots[i] = LoadedDisplayTrack(
        route: route,
        points: cached,
        index: i,
      );
      bumpProgress();
    } else {
      missIndexes.add(i);
    }
  }

  if (missIndexes.isEmpty) {
    return [for (final s in slots) if (s != null) s];
  }

  var nextMiss = 0;
  Future<void> worker() async {
    while (true) {
      if (isCancelled?.call() == true) return;
      final missPos = nextMiss++;
      if (missPos >= missIndexes.length) return;
      final i = missIndexes[missPos];
      final route = routes[i];
      final cacheKey = TrackDisplayCache.key(
        routeId: route.id,
        maxPoints: maxPoints,
        minSpacingMeters: minSpacingMeters,
        pointCount: route.pointCount,
        fingerprint: route.trackFingerprint,
      );
      try {
        final xml = await repo.readTrackContent(route);
        if (isCancelled?.call() == true) return;
        final coords = await compute(
          parseXmlForMapDisplayCoords,
          MapDisplayParseRequest(
            xml: xml,
            maxPoints: maxPoints,
            minSpacingMeters: minSpacingMeters,
          ),
        );
        if (isCancelled?.call() == true) return;
        final points = _coordsToLatLngs(coords);
        if (points.length >= 2) {
          TrackDisplayCache.instance.put(cacheKey, points);
          slots[i] = LoadedDisplayTrack(
            route: route,
            points: points,
            index: i,
          );
        }
      } catch (_) {
        // Skip unreadable routes; keep whatever else loaded.
      }
      bumpProgress();
      // Let the UI thread paint progress between isolate jobs — without
      // this, back-to-back compute() calls starved frames on Android.
      await Future<void>.delayed(Duration.zero);
    }
  }

  final workers = math.min(kTrackDisplayLoadConcurrency, missIndexes.length);
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);

  if (isCancelled?.call() == true) return const [];
  return [for (final s in slots) if (s != null) s];
}
