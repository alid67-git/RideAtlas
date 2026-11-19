import '../models/track_point.dart';
import 'daily_analysis.dart';
import 'gpx_parser.dart';

/// Outcome of folding an external track into a live multi-day recording.
class LiveRecordingMergeResult {
  const LiveRecordingMergeResult({
    required this.points,
    required this.replacedDays,
    required this.addedPointCount,
  });

  /// Full ordered buffer after the merge (glitch-filtered).
  final List<TrackPoint> points;

  /// Local calendar days whose live points were replaced by the import.
  final List<DateTime> replacedDays;

  /// Timed points taken from the import (before glitch filtering).
  final int addedPointCount;
}

/// Keeps live points whose local day is **not** present in [incoming], then
/// inserts every timed [incoming] point and sorts by GPS time.
///
/// Used to fill missing days (or overwrite a bad day) in an unfinished
/// multi-day recording, then continue GPS afterward.
LiveRecordingMergeResult mergePointsReplacingImportedDays({
  required List<TrackPoint> existing,
  required List<TrackPoint> incoming,
}) {
  final importedDays = <DateTime>{};
  final timedIncoming = <TrackPoint>[];
  for (final p in incoming) {
    final t = p.time;
    if (t == null) continue;
    importedDays.add(calendarDayLocal(t));
    timedIncoming.add(p);
  }
  if (timedIncoming.isEmpty) {
    return LiveRecordingMergeResult(
      points: List<TrackPoint>.of(existing),
      replacedDays: const [],
      addedPointCount: 0,
    );
  }

  final kept = <TrackPoint>[];
  for (final p in existing) {
    final t = p.time;
    if (t == null) {
      kept.add(p);
      continue;
    }
    if (!importedDays.contains(calendarDayLocal(t))) {
      kept.add(p);
    }
  }

  final merged = <TrackPoint>[...kept, ...timedIncoming];
  merged.sort((a, b) {
    final at = a.time;
    final bt = b.time;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return at.compareTo(bt);
  });

  final cleaned = filterImplausiblePoints(merged);
  final days = importedDays.toList()..sort();
  return LiveRecordingMergeResult(
    points: cleaned,
    replacedDays: days,
    addedPointCount: timedIncoming.length,
  );
}
