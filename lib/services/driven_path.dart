import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';

/// Day Atlas–style “driven” path math: thin to ~1 min anchors, drop noise /
/// stationary jitter / teleports / long gaps, cancel short A↔B courtyard
/// oscillations. Used for day-card km (and active riding time), not for
/// drawing the raw red polyline.
const _distance = Distance();

const kPathCompareInterval = Duration(minutes: 1);
const kPathNoiseFloorM = 15.0;
const kPathStationarySpeedKmh = 4.0;
const kMaxRealisticSpeedKmh = 120.0;
const kMaxSegmentGap = Duration(minutes: 5);
const kMaxContinuousMeters = 2000.0;
const kPathOscillationMaxMeters = 120.0;
const kPathOscillationDot = -0.3;
const kJumpHardCapMeters = 30000.0;

class DrivenPathLeg {
  const DrivenPathLeg({
    required this.distanceMeters,
    required this.duration,
    required this.dLat,
    required this.dLon,
  });

  final double distanceMeters;
  final Duration duration;
  final double dLat;
  final double dLon;
}

/// Sum of [drivenPathLegs] lengths in metres.
double drivenDistanceMeters(List<TrackPoint> points) {
  var sum = 0.0;
  for (final leg in drivenPathLegs(points)) {
    sum += leg.distanceMeters;
  }
  return sum;
}

/// Sum of durations of accepted path legs.
Duration drivenActiveDuration(List<TrackPoint> points) {
  var sum = Duration.zero;
  for (final leg in drivenPathLegs(points)) {
    sum += leg.duration;
  }
  return sum;
}

List<DrivenPathLeg> drivenPathLegs(List<TrackPoint> points) {
  final anchors = _pathAnchors(points);
  if (anchors.length < 2) return const [];

  final out = <DrivenPathLeg>[];
  for (var i = 1; i < anchors.length; i++) {
    final seg = _pathSegment(anchors[i - 1], anchors[i]);
    if (seg == null) continue;
    if (out.isNotEmpty && _isCourtyardOscillation(out.last, seg)) {
      out.removeLast();
      continue;
    }
    out.add(seg);
  }
  return out;
}

List<TrackPoint> _pathAnchors(List<TrackPoint> points) {
  if (points.length < 3) return List<TrackPoint>.from(points);
  final out = <TrackPoint>[points.first];
  final lastIndex = points.length - 1;
  for (var i = 1; i < lastIndex; i++) {
    final p = points[i];
    final prevT = out.last.time;
    final t = p.time;
    if (prevT == null || t == null) {
      out.add(p);
      continue;
    }
    if (t.difference(prevT) >= kPathCompareInterval) {
      out.add(p);
    }
  }
  final end = points.last;
  final last = out.last;
  if (last.time != end.time ||
      last.latLng.latitude != end.latLng.latitude ||
      last.latLng.longitude != end.latLng.longitude) {
    out.add(end);
  }
  return out;
}

bool _isJump(TrackPoint previous, TrackPoint candidate) {
  final dist = _distance(previous.latLng, candidate.latLng);
  if (dist >= kJumpHardCapMeters) return true;
  final prevT = previous.time;
  final curT = candidate.time;
  if (prevT == null || curT == null) return dist > 50;
  final dt = curT.difference(prevT);
  if (dt.inMilliseconds <= 0) return dist > 50;
  final speedKmh = (dist / (dt.inMilliseconds / 1000.0)) * 3.6;
  return speedKmh > kMaxRealisticSpeedKmh;
}

DrivenPathLeg? _pathSegment(TrackPoint prev, TrackPoint cur) {
  final prevT = prev.time;
  final curT = cur.time;
  if (prevT == null || curT == null) return null;
  final dt = curT.difference(prevT);
  if (dt.inMilliseconds <= 0 || dt > kMaxSegmentGap) return null;
  final distM = _distance(prev.latLng, cur.latLng);
  if (distM < kPathNoiseFloorM) return null;
  if (distM >= kMaxContinuousMeters) return null;
  if (_isJump(prev, cur)) return null;
  final speedKmh = (distM / (dt.inMilliseconds / 1000.0)) * 3.6;
  if (speedKmh < kPathStationarySpeedKmh || speedKmh > kMaxRealisticSpeedKmh) {
    return null;
  }
  return DrivenPathLeg(
    distanceMeters: distM,
    duration: dt,
    dLat: cur.latLng.latitude - prev.latLng.latitude,
    dLon: cur.latLng.longitude - prev.latLng.longitude,
  );
}

bool _isCourtyardOscillation(DrivenPathLeg a, DrivenPathLeg b) {
  if (a.distanceMeters > kPathOscillationMaxMeters) return false;
  if (b.distanceMeters > kPathOscillationMaxMeters) return false;
  final aLen = math.sqrt(a.dLat * a.dLat + a.dLon * a.dLon);
  final bLen = math.sqrt(b.dLat * b.dLat + b.dLon * b.dLon);
  if (aLen < 1e-12 || bLen < 1e-12) return false;
  final dot = (a.dLat * b.dLat + a.dLon * b.dLon) / (aLen * bLen);
  return dot <= kPathOscillationDot;
}
