import 'package:flutter/material.dart' show Color;
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import 'route_geography.dart';

const _distance = Distance();

/// Cycled per day so multi-day trips can be told apart at a glance, both on
/// the map (one polyline per day) and in the daily analysis tab.
const dayColorPalette = <Color>[
  Color(0xFFE53935), // red
  Color(0xFF1E88E5), // blue
  Color(0xFF43A047), // green
  Color(0xFFFB8C00), // orange
  Color(0xFF8E24AA), // purple
  Color(0xFF00897B), // teal
  Color(0xFF6D4C41), // brown
  Color(0xFFD81B60), // pink
  Color(0xFF3949AB), // indigo
  Color(0xFFF9A825), // amber
  Color(0xFF00ACC1), // cyan
  Color(0xFFF4511E), // deep orange
];

Color colorForDay(int zeroBasedIndex) =>
    dayColorPalette[zeroBasedIndex % dayColorPalette.length];

/// Per-day breakdown of a (potentially multi-day) track: that day's own
/// distance, elevation, riding/rest time, and (once geography is available)
/// the countries crossed.
class DayStats {
  const DayStats({
    required this.dayNumber,
    required this.date,
    required this.points,
    required this.color,
    required this.distanceKm,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.maxElevation,
    required this.minElevation,
    required this.ridingDuration,
    required this.restDuration,
    required this.countries,
  });

  final int dayNumber;

  /// Local midnight of this calendar day - a label, not a precise instant.
  final DateTime date;
  final List<TrackPoint> points;
  final Color color;
  final double distanceKm;
  final double elevationGainM;
  final double elevationLossM;
  final double? maxElevation;
  final double? minElevation;

  /// Wall-clock span of the day's points, minus [restDuration]. Null if the
  /// day has fewer than two timestamped points.
  final Duration? ridingDuration;

  /// Sum of detected-stop durations ([RouteGeography.stops]) that started on
  /// this day. Zero (not null) when geography hasn't been computed yet, so
  /// [ridingDuration] still reflects the raw wall-clock span until it has.
  final Duration restDuration;

  final List<String> countries;
}

/// Midnight of the device-local calendar day that [t] falls on - used as a
/// day-bucket key, not a precise instant. GPS timestamps are usually UTC
/// (see RecordingLocationService / GPX `time`), so using [DateTime.utc]'s
/// Y/M/D directly would put late-evening / early-morning rides on the
/// wrong calendar day for anyone east or west of UTC (e.g. Turkey UTC+3:
/// a 01:00 local ride on the 28th is still the 27th in UTC, and gets
/// counted into "yesterday").
DateTime calendarDayLocal(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Splits a track into device-local calendar-day segments for multi-day
/// trips. Returns an empty list if no point carries a timestamp - day
/// splitting needs GPS time data. [geography] is optional; when supplied
/// (once the route's country/stop analysis has finished), rest time and
/// countries are filled in per day instead of being left at defaults.
List<DayStats> splitIntoDays(
  List<TrackPoint> points, {
  RouteGeography? geography,
}) {
  final groups = <DateTime, List<TrackPoint>>{};
  for (final p in points) {
    final t = p.time;
    if (t == null) continue;
    final day = calendarDayLocal(t);
    groups.putIfAbsent(day, () => []).add(p);
  }
  if (groups.isEmpty) return const [];

  final days = groups.keys.toList()..sort();
  final result = <DayStats>[];

  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final dayPoints = groups[day]!;

    var distanceKm = 0.0;
    var gain = 0.0;
    var loss = 0.0;
    double? minEle;
    double? maxEle;

    for (var j = 0; j < dayPoints.length; j++) {
      final p = dayPoints[j];
      if (p.elevation != null) {
        minEle = minEle == null
            ? p.elevation
            : (p.elevation! < minEle ? p.elevation : minEle);
        maxEle = maxEle == null
            ? p.elevation
            : (p.elevation! > maxEle ? p.elevation : maxEle);
      }
      if (j > 0) {
        final prev = dayPoints[j - 1];
        distanceKm += _distance(prev.latLng, p.latLng) / 1000.0;
        if (prev.elevation != null && p.elevation != null) {
          final diff = p.elevation! - prev.elevation!;
          if (diff > 0) {
            gain += diff;
          } else {
            loss += -diff;
          }
        }
      }
    }

    Duration? span;
    final first = dayPoints.first.time;
    final last = dayPoints.last.time;
    if (first != null && last != null && last.isAfter(first)) {
      span = last.difference(first);
    }

    var restDuration = Duration.zero;
    final countries = <String>[];
    if (geography != null) {
      for (final stop in geography.stops) {
        final s = stop.start;
        if (s == null) continue;
        if (calendarDayLocal(s) == day) {
          restDuration += stop.duration;
        }
      }

      final dayEnd = day.add(const Duration(days: 1));
      for (final leg in geography.legs) {
        final legStart = leg.start;
        final legEnd = leg.end;
        if (legStart == null || legEnd == null) continue;
        final overlaps = legStart.isBefore(dayEnd) && legEnd.isAfter(day);
        if (overlaps && !countries.contains(leg.country)) {
          countries.add(leg.country);
        }
      }
    }

    Duration? riding;
    if (span != null) {
      final r = span - restDuration;
      riding = r.isNegative ? Duration.zero : r;
    }

    result.add(
      DayStats(
        dayNumber: i + 1,
        date: day,
        points: dayPoints,
        color: colorForDay(i),
        distanceKm: distanceKm,
        elevationGainM: gain,
        elevationLossM: loss,
        maxElevation: maxEle,
        minElevation: minEle,
        ridingDuration: riding,
        restDuration: restDuration,
        countries: countries,
      ),
    );
  }

  return result;
}
