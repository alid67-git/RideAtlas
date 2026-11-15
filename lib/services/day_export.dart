import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import '../models/waypoint.dart';
import 'daily_analysis.dart';
import 'daily_backup.dart';
import 'track_io.dart';

const _distance = Distance();

/// How the rider wants multi-day content written out.
enum DayExportScope {
  /// One file with every point (current share behaviour).
  fullRoute,

  /// One file per selected local calendar day.
  selectedDays,
}

/// Where to put the exported file(s).
enum DayExportDestination {
  /// System share sheet (Apps, Files, Drive, AirDrop, …).
  share,

  /// Android SAF folder picker (Drive / Downloads / …).
  folder,
}

/// Result of the multi-day export chooser.
class DayExportPlan {
  const DayExportPlan({
    required this.scope,
    required this.destination,
    required this.selectedDays,
  });

  final DayExportScope scope;
  final DayExportDestination destination;

  /// Local midnights when [scope] is [DayExportScope.selectedDays].
  final List<DateTime> selectedDays;
}

/// Waypoints whose nearest timestamped track point falls on [day].
/// Waypoints with no nearby timed point are omitted from day files.
List<Waypoint> waypointsForLocalDay({
  required List<Waypoint> waypoints,
  required List<TrackPoint> allPoints,
  required DateTime day,
}) {
  final key = DateTime(day.year, day.month, day.day);
  final timed = [
    for (final p in allPoints)
      if (p.time != null) p,
  ];
  if (timed.isEmpty || waypoints.isEmpty) return const [];

  final out = <Waypoint>[];
  for (final w in waypoints) {
    TrackPoint? nearest;
    var best = double.infinity;
    for (final p in timed) {
      final d = _distance(w.latLng, p.latLng);
      if (d < best) {
        best = d;
        nearest = p;
      }
    }
    final t = nearest?.time;
    if (t != null && calendarDayLocal(t) == key) {
      out.add(w);
    }
  }
  return out;
}

/// Builds one export blob for [day] (GPX/KML/KMZ). Null if that day is empty.
TrackExport? buildDayTrackExport({
  required List<TrackPoint> allPoints,
  required List<Waypoint> waypoints,
  required DateTime day,
  required TrackFormat format,
  String? nameOverride,
}) {
  final dayPoints = pointsForLocalDay(allPoints, day);
  if (dayPoints.isEmpty) return null;
  final name = nameOverride ?? dayBackupTrackName(day);
  return buildTrackExport(
    name: name,
    points: dayPoints,
    waypoints: waypointsForLocalDay(
      waypoints: waypoints,
      allPoints: allPoints,
      day: day,
    ),
    format: format,
  );
}

/// File base name (no extension) for a single calendar-day export.
///
/// Always the track day (`RideAtlas_yyyy-MM-dd`), never "today" / save time
/// and never a route display name that may contain the save timestamp.
String dayExportBaseName(DateTime day) => 'RideAtlas_${dayBackupKey(day)}';

/// File base name for a full-route export from [points]' local calendar days.
///
/// One day → `RideAtlas_yyyy-MM-dd`; several → `RideAtlas_first_last`.
/// Falls back to a sanitized [fallbackName] only when no timed points exist.
String fullRouteExportBaseName(
  List<TrackPoint> points, {
  String? fallbackName,
}) {
  final days = localDaysInPoints(points);
  if (days.length == 1) return dayExportBaseName(days.single);
  if (days.length >= 2) {
    return 'RideAtlas_${dayBackupKey(days.first)}_${dayBackupKey(days.last)}';
  }
  final safe = (fallbackName ?? '').trim().replaceAll(
    RegExp(r'[\\/:*?"<>|]'),
    '_',
  );
  return safe.isEmpty ? 'RideAtlas' : safe;
}
