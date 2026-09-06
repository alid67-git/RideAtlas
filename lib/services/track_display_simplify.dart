import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Max vertices drawn for a **single** route map. An 8-day GPX at 1–2 s can
/// be 50k–200k points; painting all of them on every pan/pinch freezes the UI.
const kMapDisplayMaxPoints = 8000;

/// Soft warning before "show all" opens this many routes on one map.
const kShowAllRoutesSoftCap = 10;

/// Hard refuse above this — even simplified geometry would thrash memory.
/// (~20 long rides already stress low-RAM Androids; keep headroom small.)
const kShowAllRoutesHardCap = 24;

/// Cap total display vertices across every polyline on one map. Without this,
/// 20 × 800-point overlays still freeze Android pan/pinch after load.
const kMapDisplayTotalPointsBudget = 6000;

/// Max GPS photo pins drawn on a multi-route / overlay map (icons only).
const kMapPhotoPinCap = 24;

/// Skip photo pins entirely once this many routes share the map — scanning
/// PhotoRepository for every route during build was part of the show-all stall.
const kMapPhotoPinRouteCap = 8;

const _distance = Distance();

/// Per-route display budget when [routeCount] tracks share one map.
///
/// Uses a **global** vertex budget so ~20 Android tracks stay interactive
/// (older code only capped per-route, so 20×800 still locked the UI).
({int maxPoints, double minSpacingMeters}) mapDisplayBudget(int routeCount) {
  if (routeCount <= 1) {
    return (maxPoints: kMapDisplayMaxPoints, minSpacingMeters: 15);
  }

  final perRoute = math.max(
    80,
    kMapDisplayTotalPointsBudget ~/ routeCount,
  );

  if (routeCount <= 5) {
    return (
      maxPoints: math.min(3000, perRoute),
      minSpacingMeters: 20,
    );
  }
  if (routeCount <= 10) {
    return (
      maxPoints: math.min(1200, perRoute),
      minSpacingMeters: 35,
    );
  }
  if (routeCount <= 16) {
    return (
      maxPoints: math.min(500, perRoute),
      minSpacingMeters: 50,
    );
  }
  // ~20 tracks: ~250–300 pts each, aggressive spacing.
  return (
    maxPoints: math.min(300, perRoute),
    minSpacingMeters: 70,
  );
}

/// Drops redundant GPS vertices for **display only** (analysis/export keep
/// the full list). Always keeps the first and last point.
///
/// Long rides are stride-sampled **before** the haversine spacing loop so
/// isolate work stays O(display) instead of O(raw GPS) — critical when
/// several large GPX files parse in parallel on Android.
List<LatLng> latLngsForMapDisplay(
  List<LatLng> points, {
  int maxPoints = kMapDisplayMaxPoints,
  double minSpacingMeters = 15,
}) {
  if (points.length <= 2) return List<LatLng>.from(points);
  if (points.length <= maxPoints && minSpacingMeters <= 0) {
    return List<LatLng>.from(points);
  }

  // Coarse stride first: 100k-point GPX × Distance() in 2–4 isolates ANRs.
  var working = points;
  final coarseTarget = math.max(maxPoints * 4, 400);
  if (working.length > coarseTarget) {
    final stride = math.max(1, working.length ~/ coarseTarget);
    final sampled = <LatLng>[working.first];
    for (var i = stride; i < working.length - 1; i += stride) {
      sampled.add(working[i]);
    }
    if (sampled.last != working.last) sampled.add(working.last);
    working = sampled;
  }

  final spaced = <LatLng>[working.first];
  for (var i = 1; i < working.length - 1; i++) {
    final p = working[i];
    if (_distance(spaced.last, p) >= minSpacingMeters) {
      spaced.add(p);
    }
  }
  if (spaced.last != working.last) spaced.add(working.last);

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
