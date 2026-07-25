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
  );
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

class ElevationSample {
  const ElevationSample({required this.distanceKm, required this.elevation});
  final double distanceKm;
  final double elevation;
}
