import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Max vertices drawn for a **single** route map. An 8-day GPX at 1–2 s can
/// be 50k–200k points; painting all of them on every pan/pinch freezes the UI.
const kMapDisplayMaxPoints = 8000;

/// Soft warning before "show all" opens this many routes on one map.
const kShowAllRoutesSoftCap = 12;

/// Hard refuse above this — even simplified geometry would thrash memory.
const kShowAllRoutesHardCap = 40;

/// Max GPS photo pins drawn on a multi-route / overlay map (icons only).
const kMapPhotoPinCap = 40;

const _distance = Distance();

/// Tighter display budget when many routes share one map.
({int maxPoints, double minSpacingMeters}) mapDisplayBudget(int routeCount) {
  if (routeCount <= 1) {
    return (maxPoints: kMapDisplayMaxPoints, minSpacingMeters: 15);
  }
  if (routeCount <= 5) {
    return (maxPoints: 3000, minSpacingMeters: 20);
  }
  if (routeCount <= 12) {
    return (maxPoints: 1500, minSpacingMeters: 30);
  }
  if (routeCount <= 25) {
    return (maxPoints: 800, minSpacingMeters: 40);
  }
  return (maxPoints: 400, minSpacingMeters: 50);
}

/// Drops redundant GPS vertices for **display only** (analysis/export keep
/// the full list). Always keeps the first and last point.
List<LatLng> latLngsForMapDisplay(
  List<LatLng> points, {
  int maxPoints = kMapDisplayMaxPoints,
  double minSpacingMeters = 15,
}) {
  if (points.length <= 2) return List<LatLng>.from(points);
  if (points.length <= maxPoints && minSpacingMeters <= 0) {
    return List<LatLng>.from(points);
  }

  final spaced = <LatLng>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    if (_distance(spaced.last, p) >= minSpacingMeters) {
      spaced.add(p);
    }
  }
  if (spaced.last != points.last) spaced.add(points.last);

  if (spaced.length <= maxPoints) return spaced;

  final step = (spaced.length / maxPoints).ceil();
  final out = <LatLng>[spaced.first];
  for (var i = step; i < spaced.length - 1; i += step) {
    out.add(spaced[i]);
  }
  if (out.last != spaced.last) out.add(spaced.last);
  return out;
}

/// Result of a cheap nearest-track hit-test for tap-to-label.
class TrackHit {
  const TrackHit({
    required this.id,
    required this.name,
    required this.point,
  });

  final String id;
  final String name;
  final LatLng point;
}

/// Fast-ish nearest polyline for map taps. Samples vertices (stride) and
/// rejects by a crude degree bbox before any haversine, so show-all maps
/// with tens of thousands of display points stay responsive.
TrackHit? findNearestTrackHit({
  required LatLng tap,
  required double zoom,
  required Iterable<({String id, String name, List<LatLng> points})> tracks,
}) {
  final thresholdM = 35.0 * (1 << math.max(0, (15 - zoom).round()));
  // ~1e-5 deg ≈ 1.1 m at equator; pad the bbox.
  final padDeg = (thresholdM / 111000.0) * 1.5;

  String? bestId;
  String? bestName;
  LatLng? bestPoint;
  var bestM = thresholdM;

  for (final track in tracks) {
    final points = track.points;
    if (points.length < 2) continue;

    // Sample so a 4k-point line costs ~200 distance checks, not 12k.
    final stride = math.max(1, points.length ~/ 200);

    for (var i = 0; i < points.length; i += stride) {
      final p = points[i];
      if ((p.latitude - tap.latitude).abs() > padDeg ||
          (p.longitude - tap.longitude).abs() > padDeg) {
        continue;
      }
      final m = _distance(tap, p);
      if (m < bestM) {
        bestM = m;
        bestId = track.id;
        bestName = track.name;
        bestPoint = p;
      }
    }
    // Always consider the tip.
    final tip = points.last;
    if ((tip.latitude - tap.latitude).abs() <= padDeg &&
        (tip.longitude - tap.longitude).abs() <= padDeg) {
      final m = _distance(tap, tip);
      if (m < bestM) {
        bestM = m;
        bestId = track.id;
        bestName = track.name;
        bestPoint = tip;
      }
    }
  }

  if (bestId == null || bestName == null || bestPoint == null) return null;
  return TrackHit(id: bestId, name: bestName, point: bestPoint);
}
