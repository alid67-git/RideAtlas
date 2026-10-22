import '../models/track_point.dart';
import 'daily_analysis.dart';
import 'track_io.dart';

/// Local-calendar-day key `yyyy-MM-dd` (device timezone), matching
/// [calendarDayLocal] / the daily analysis tab.
String dayBackupKey(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// GPX file name for a single-day backup (Drive / SAF folder).
String dayBackupFileName(DateTime day) => 'RideAtlas_${dayBackupKey(day)}.gpx';

/// Track display name embedded in the GPX metadata.
String dayBackupTrackName(DateTime day) => 'RideAtlas ${dayBackupKey(day)}';

/// Points that fall on [day] (local calendar), in original order.
/// Timeless points are omitted - same rule as [splitIntoDays].
List<TrackPoint> pointsForLocalDay(List<TrackPoint> points, DateTime day) {
  final key = DateTime(day.year, day.month, day.day);
  return [
    for (final p in points)
      if (p.time != null && calendarDayLocal(p.time!) == key) p,
  ];
}

/// Distinct local calendar days present in [points], ascending.
List<DateTime> localDaysInPoints(List<TrackPoint> points) {
  final days = <DateTime>{};
  for (final p in points) {
    final t = p.time;
    if (t == null) continue;
    days.add(calendarDayLocal(t));
  }
  final list = days.toList()..sort();
  return list;
}

/// Builds a GPX containing **only** [day]'s points - not the full multi-day
/// session. Returns null when that day has no timestamped points.
String? buildDayBackupGpx({
  required List<TrackPoint> allPoints,
  required DateTime day,
}) {
  final dayPoints = pointsForLocalDay(allPoints, day);
  if (dayPoints.isEmpty) return null;
  return exportTrack(
    name: dayBackupTrackName(day),
    points: dayPoints,
    waypoints: const [],
    format: TrackFormat.gpx,
  );
}
