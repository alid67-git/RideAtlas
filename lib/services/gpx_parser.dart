import 'package:gpx/gpx.dart' as gpxlib;
import 'package:latlong2/latlong.dart';

import '../models/gpx_route.dart';
import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';

const _distance = Distance();

/// Parses raw GPX XML into track points and waypoints.
///
/// Track points come from `<trk>/<trkseg>` segments (all segments of all
/// tracks are concatenated in document order). If a file has no tracks but
/// does have a `<rte>`, that is used as a fallback so plain route files still
/// render a line.
ParsedTrack parseGpxXml(String xml) {
  final gpx = gpxlib.GpxReader().fromString(xml);

  final points = <TrackPoint>[];
  for (final trk in gpx.trks) {
    for (final seg in trk.trksegs) {
      for (final pt in seg.trkpts) {
        if (pt.lat == null || pt.lon == null) continue;
        points.add(
          TrackPoint(
            latLng: LatLng(pt.lat!, pt.lon!),
            elevation: pt.ele,
            time: pt.time,
          ),
        );
      }
    }
  }

  if (points.isEmpty) {
    for (final rte in gpx.rtes) {
      for (final pt in rte.rtepts) {
        if (pt.lat == null || pt.lon == null) continue;
        points.add(
          TrackPoint(
            latLng: LatLng(pt.lat!, pt.lon!),
            elevation: pt.ele,
            time: pt.time,
          ),
        );
      }
    }
  }

  final waypoints = <Waypoint>[
    for (final wpt in gpx.wpts)
      if (wpt.lat != null && wpt.lon != null)
        Waypoint(
          latLng: LatLng(wpt.lat!, wpt.lon!),
          name: wpt.name,
          description: wpt.desc,
        ),
  ];

  final suggestedName = (gpx.metadata?.name?.trim().isNotEmpty ?? false)
      ? gpx.metadata!.name!.trim()
      : (gpx.trks.isNotEmpty &&
            (gpx.trks.first.name?.trim().isNotEmpty ?? false))
      ? gpx.trks.first.name!.trim()
      : null;

  return ParsedTrack(
    points: points,
    waypoints: waypoints,
    suggestedName: suggestedName,
  );
}

/// Computes summary stats (distance, elevation gain/loss, duration, bounds)
/// for a parsed track, to be cached in a [GpxRoute].
GpxRoute buildRouteMetadata({
  required String id,
  required String name,
  required DateTime importedAt,
  required ParsedTrack parsed,
  int? batteryStartPercent,
  int? batteryEndPercent,
}) {
  final points = parsed.points;

  double distanceMeters = 0;
  double elevationGain = 0;
  double elevationLoss = 0;
  double? minEle;
  double? maxEle;

  double north = -90, south = 90, east = -180, west = 180;

  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final lat = p.latLng.latitude;
    final lon = p.latLng.longitude;
    if (lat > north) north = lat;
    if (lat < south) south = lat;
    if (lon > east) east = lon;
    if (lon < west) west = lon;

    if (p.elevation != null) {
      minEle = minEle == null
          ? p.elevation
          : (p.elevation! < minEle ? p.elevation : minEle);
      maxEle = maxEle == null
          ? p.elevation
          : (p.elevation! > maxEle ? p.elevation : maxEle);
    }

    if (i > 0) {
      final prev = points[i - 1];
      distanceMeters += _distance(prev.latLng, p.latLng);
      if (prev.elevation != null && p.elevation != null) {
        final diff = p.elevation! - prev.elevation!;
        if (diff > 0) {
          elevationGain += diff;
        } else {
          elevationLoss += -diff;
        }
      }
    }
  }

  int? durationSeconds;
  if (points.isNotEmpty) {
    final first = points.first.time;
    final last = points.last.time;
    if (first != null && last != null && last.isAfter(first)) {
      durationSeconds = last.difference(first).inSeconds;
    }
  }

  if (points.isEmpty) {
    north = 0;
    south = 0;
    east = 0;
    west = 0;
  }

  return GpxRoute(
    id: id,
    name: name,
    importedAt: importedAt,
    distanceMeters: distanceMeters,
    elevationGainMeters: elevationGain,
    elevationLossMeters: elevationLoss,
    minElevation: minEle,
    maxElevation: maxEle,
    durationSeconds: durationSeconds,
    pointCount: points.length,
    north: north,
    south: south,
    east: east,
    west: west,
    batteryStartPercent: batteryStartPercent,
    batteryEndPercent: batteryEndPercent,
  );
}

/// Cumulative elevation gain/loss across [points], same simple point-to-point
/// sum [buildRouteMetadata] uses for a saved route's own totals - so a live
/// in-progress figure (see RecordScreen's info page) already matches what
/// the route will show once saved, no separate reconciliation needed.
({double gain, double loss}) computeElevationChange(List<TrackPoint> points) {
  double gain = 0;
  double loss = 0;
  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1].elevation;
    final curr = points[i].elevation;
    if (prev == null || curr == null) continue;
    final diff = curr - prev;
    if (diff > 0) {
      gain += diff;
    } else {
      loss += -diff;
    }
  }
  return (gain: gain, loss: loss);
}

/// Plain point-to-point distance sum - the same total [buildRouteMetadata]
/// uses for [GpxRoute.distanceMeters], exposed here too so a derived figure
/// (like an average speed) can divide by exactly this distance instead of
/// quietly using a smaller one (e.g. [SpeedStats.averageMovingKmh]'s, which
/// only counts segments its own speed filter accepted).
double totalDistanceKm(List<TrackPoint> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += _distance(points[i - 1].latLng, points[i].latLng) / 1000;
  }
  return total;
}

/// Above any real vehicle speed this app expects to record - a fix that
/// implies faster than this since the last *plausible* point before it is a
/// reflected/multipath GPS glitch (common near junctions, tall buildings,
/// underpasses), not real motion. Matches the threshold GpsRecorder rejects
/// live during recording, so a route recorded before that live filter
/// existed (or imported from another app/device) can be cleaned up the same
/// way after the fact.
const maxPlausibleTrackSpeedKmh = 300.0;

/// A single-hop jump has to imply at least this speed *and* cover at least
/// [_excursionMinJumpMeters] before [findExcursionPointIndices] even
/// considers it a candidate - low, deliberately, so it catches jumps a real
/// motorcycle ride would never produce, without also catching the routine
/// couple-km/h-implying jitter GPS reports while genuinely stationary (a
/// few meters of noise over a 1-2s gap can misleadingly imply tens of
/// km/h on its own, which a lower distance-only or speed-only gate would
/// wrongly flag).
const _excursionTriggerKmh = 60.0;
const _excursionMinJumpMeters = 150.0;

/// How close a later point has to land to the pre-excursion position to
/// count as "came back" - larger than ordinary GPS jitter (tens of
/// meters) so a real nearby-but-not-identical revisit doesn't confuse the
/// detector into merging unrelated points.
const _excursionReturnRadiusMeters = 60.0;

/// How many points ahead to search for a return before giving up and
/// treating the jump as real (sustained fast riding, or a genuine GPS gap)
/// rather than a glitch - a real excursion glitch snaps back within
/// seconds to a couple of minutes, not further out.
const _excursionMaxLookaheadPoints = 150;

/// Indices of points in [points] that imply a physically-impossible speed
/// jump from the last plausible point before them. Comparing against the
/// last point that itself passed this check (not just the previous point)
/// means a run of several consecutive bad fixes gets flagged in full rather
/// than each one anchoring the next comparison to more noise. This alone
/// only catches a jump that's *instantly* impossible (over
/// [maxPlausibleTrackSpeedKmh]) - see [findExcursionPointIndices] for the
/// more common case of a jump that's individually fast-but-plausible yet
/// snaps back to nearly where it started a few points later (confirmed in
/// practice: a device sitting still reported one frozen, wrong coordinate
/// for about a minute, then reported the true position again - each hop
/// alone implied "only" ~140 km/h, not an instantly-rejectable spike).
/// Used both to silently clean a route for display
/// ([filterImplausiblePoints]) and to let a rider review exactly which
/// points would be removed before deleting them from a saved route (see the
/// route anomaly editor).
List<int> findImplausiblePointIndices(
  List<TrackPoint> points, {
  double maxKmh = maxPlausibleTrackSpeedKmh,
}) {
  final flagged = <int>{
    ..._findInstantSpikeIndices(points, maxKmh: maxKmh),
    ...findExcursionPointIndices(points),
  }.toList()..sort();
  return flagged;
}

List<int> _findInstantSpikeIndices(
  List<TrackPoint> points, {
  double maxKmh = maxPlausibleTrackSpeedKmh,
}) {
  final flagged = <int>[];
  TrackPoint? lastPlausible;
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final lastTime = lastPlausible?.time;
    if (lastPlausible == null || lastTime == null || p.time == null) {
      lastPlausible = p;
      continue;
    }
    final dtSeconds = p.time!.difference(lastTime).inMilliseconds / 1000.0;
    if (dtSeconds <= 0) {
      lastPlausible = p;
      continue;
    }
    final meters = _distance(lastPlausible.latLng, p.latLng);
    final impliedKmh = (meters / dtSeconds) * 3.6;
    if (impliedKmh > maxKmh) {
      flagged.add(i);
      continue;
    }
    lastPlausible = p;
  }
  return flagged;
}

/// Indices of points that form a "spike and return": the track suddenly
/// jumps far from its last stable point fast enough to be implausible, then
/// - within [_excursionMaxLookaheadPoints] points - lands back within
/// [_excursionReturnRadiusMeters] of that same stable point. Real riding
/// doesn't do this (a genuine detour takes time proportional to the
/// distance covered and doesn't return to the exact same spot); a reflected
/// or cached GPS fix does. Points strictly between the jump and the return
/// are flagged; the returning point itself becomes the new stable point so
/// scanning continues cleanly rather than re-triggering on it.
List<int> findExcursionPointIndices(
  List<TrackPoint> points, {
  double triggerKmh = _excursionTriggerKmh,
  double minJumpMeters = _excursionMinJumpMeters,
  double returnRadiusMeters = _excursionReturnRadiusMeters,
  int maxLookaheadPoints = _excursionMaxLookaheadPoints,
}) {
  final flagged = <int>[];
  var stableIndex = 0;
  var i = 1;
  while (i < points.length) {
    final stable = points[stableIndex];
    final p = points[i];
    final meters = _distance(stable.latLng, p.latLng);
    var isCandidate = false;
    if (meters >= minJumpMeters) {
      final t0 = stable.time;
      final t1 = p.time;
      if (t0 != null && t1 != null) {
        final dtSeconds = t1.difference(t0).inMilliseconds / 1000.0;
        isCandidate = dtSeconds <= 0 || (meters / dtSeconds) * 3.6 >= triggerKmh;
      } else {
        isCandidate = true;
      }
    }
    if (!isCandidate) {
      stableIndex = i;
      i++;
      continue;
    }
    final limit = (i + maxLookaheadPoints < points.length)
        ? i + maxLookaheadPoints
        : points.length;
    var returnIndex = -1;
    for (var j = i + 1; j < limit; j++) {
      if (_distance(stable.latLng, points[j].latLng) <= returnRadiusMeters) {
        returnIndex = j;
        break;
      }
    }
    if (returnIndex == -1) {
      // Never comes back nearby within the window - treat as real movement
      // (sustained fast riding, or a genuine GPS gap), not a glitch.
      stableIndex = i;
      i++;
      continue;
    }
    for (var k = i; k < returnIndex; k++) {
      flagged.add(k);
    }
    stableIndex = returnIndex;
    i = returnIndex + 1;
  }
  return flagged;
}

/// [points] with every [findImplausiblePointIndices] index removed - used to
/// clean up a saved route's map/stats display without touching what's
/// actually stored on disk. A rider who wants the glitch gone from the
/// saved file itself (e.g. before sharing it) can still remove it for real
/// through the route anomaly editor.
List<TrackPoint> filterImplausiblePoints(
  List<TrackPoint> points, {
  double maxKmh = maxPlausibleTrackSpeedKmh,
}) {
  final flagged = findImplausiblePointIndices(points, maxKmh: maxKmh).toSet();
  if (flagged.isEmpty) return points;
  return [
    for (var i = 0; i < points.length; i++)
      if (!flagged.contains(i)) points[i],
  ];
}

/// Cumulative distance (km) vs elevation (m) samples, for the elevation
/// profile chart. Points without elevation data are skipped.
List<ElevationSample> buildElevationProfile(List<TrackPoint> points) {
  final samples = <ElevationSample>[];
  double cumulativeKm = 0;
  for (var i = 0; i < points.length; i++) {
    if (i > 0) {
      cumulativeKm += _distance(points[i - 1].latLng, points[i].latLng) / 1000;
    }
    final ele = points[i].elevation;
    if (ele != null) {
      samples.add(ElevationSample(distanceKm: cumulativeKm, elevation: ele));
    }
  }
  return samples;
}

/// Instantaneous speeds between consecutive timed points.
///
/// Segments shorter than 1s, slower than 1 km/h (stopped / GPS jitter) or
/// faster than 250 km/h (implausible GPS spikes) are ignored. A segment is
/// also rejected if it implies acceleration/deceleration faster than
/// [_maxAccelerationKmhPerSec] since the last accepted reading - a single
/// bad fix jumping (and jumping back) reads as one impossibly sharp spike,
/// not real riding, and would otherwise blow out [maxKmh]/[averageMovingKmh].
/// [minKmh] / [maxKmh] / [averageMovingKmh] are therefore "while moving"
/// figures - [averageMovingKmh] is distance ÷ time over just the accepted
/// moving segments (riding-only, rests excluded), not a plain mean of the
/// per-segment kmh values. For how long the rider was actually moving, see
/// [RouteGeographyAnalyzer.
/// detectStops] instead - a per-segment speed check is too noisy (GPS
/// jitter keeps flickering a stationary rider just above/below the
/// threshold) to use as a duration figure on its own.
SpeedStats buildSpeedStats(List<TrackPoint> points) {
  const minDtSeconds = 1.0;
  const minMovingKmh = 1.0;
  const maxPlausibleKmh = 250.0;
  const maxAccelerationKmhPerSec = 30.0;

  double? minKmh;
  double? maxKmh;
  // Distance/time over every accepted moving segment, not a plain mean of
  // per-segment kmh values - a rider means "how fast was I actually going
  // while riding" (distance ÷ riding time), not an unweighted average that
  // lets a handful of short slow segments drag the figure down as much as
  // a long fast one.
  var movingMeters = 0.0;
  var movingSeconds = 0.0;
  var count = 0;
  double? lastAcceptedKmh;
  DateTime? lastAcceptedTime;

  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final t0 = prev.time;
    final t1 = curr.time;
    if (t0 == null || t1 == null) continue;

    final dtSeconds = t1.difference(t0).inMilliseconds / 1000.0;
    if (dtSeconds < minDtSeconds) continue;

    final meters = _distance(prev.latLng, curr.latLng);
    final kmh = (meters / 1000.0) / (dtSeconds / 3600.0);
    if (kmh < minMovingKmh || kmh > maxPlausibleKmh) continue;

    if (lastAcceptedKmh != null && lastAcceptedTime != null) {
      final accelDtSeconds =
          t1.difference(lastAcceptedTime).inMilliseconds / 1000.0;
      if (accelDtSeconds > 0 &&
          (kmh - lastAcceptedKmh).abs() >
              maxAccelerationKmhPerSec * accelDtSeconds) {
        continue;
      }
    }
    lastAcceptedKmh = kmh;
    lastAcceptedTime = t1;

    minKmh = minKmh == null ? kmh : (kmh < minKmh ? kmh : minKmh);
    maxKmh = maxKmh == null ? kmh : (kmh > maxKmh ? kmh : maxKmh);
    movingMeters += meters;
    movingSeconds += dtSeconds;
    count++;
  }

  return SpeedStats(
    minKmh: minKmh,
    maxKmh: maxKmh,
    averageMovingKmh: count == 0
        ? null
        : (movingMeters / 1000.0) / (movingSeconds / 3600.0),
  );
}

/// First / last GPS timestamps on the track (if present).
({DateTime? start, DateTime? end}) trackTimeRange(List<TrackPoint> points) {
  DateTime? start;
  DateTime? end;
  for (final p in points) {
    final t = p.time;
    if (t == null) continue;
    if (start == null || t.isBefore(start)) start = t;
    if (end == null || t.isAfter(end)) end = t;
  }
  return (start: start, end: end);
}

/// Net elevation change from first to last point that has elevation data.
double? netElevationChange(List<TrackPoint> points) {
  double? first;
  double? last;
  for (final p in points) {
    if (p.elevation == null) continue;
    first ??= p.elevation;
    last = p.elevation;
  }
  if (first == null || last == null) return null;
  return last - first;
}

class ElevationSample {
  const ElevationSample({required this.distanceKm, required this.elevation});
  final double distanceKm;
  final double elevation;
}

class SpeedStats {
  const SpeedStats({
    required this.minKmh,
    required this.maxKmh,
    required this.averageMovingKmh,
  });

  final double? minKmh;
  final double? maxKmh;

  /// Mean of per-segment speeds while moving (see [buildSpeedStats]).
  final double? averageMovingKmh;
}
