import 'package:intl/intl.dart';

import '../models/track_point.dart';
import 'daily_backup.dart';

/// Human-readable date (or range) for naming a finished recording.
///
/// - One calendar day: `4 Kas 2026 12:43` (first GPS time, or [fallbackStart]).
/// - Same month: `4-21 Kas 2026`.
/// - Same year, different months: `4 Kas – 21 Ara 2026`.
/// - Spans years: `4 Kas 2025 – 21 Kas 2026`.
String formatRecordingDateSpan({
  required List<TrackPoint> points,
  required String locale,
  DateTime? fallbackStart,
}) {
  final days = localDaysInPoints(points);
  if (days.isEmpty) {
    final t = (fallbackStart ?? DateTime.now()).toLocal();
    return DateFormat('d MMM yyyy HH:mm', locale).format(t);
  }
  if (days.length == 1) {
    DateTime? firstTimed;
    for (final p in points) {
      final t = p.time;
      if (t == null) continue;
      firstTimed = t.toLocal();
      break;
    }
    final t = firstTimed ?? (fallbackStart ?? days.single).toLocal();
    return DateFormat('d MMM yyyy HH:mm', locale).format(t);
  }

  final first = days.first;
  final last = days.last;
  if (first.year == last.year && first.month == last.month) {
    final monthYear = DateFormat('MMM yyyy', locale).format(last);
    return '${first.day}-${last.day} $monthYear';
  }
  if (first.year == last.year) {
    final start = DateFormat('d MMM', locale).format(first);
    final end = DateFormat('d MMM yyyy', locale).format(last);
    return '$start – $end';
  }
  final start = DateFormat('d MMM yyyy', locale).format(first);
  final end = DateFormat('d MMM yyyy', locale).format(last);
  return '$start – $end';
}
