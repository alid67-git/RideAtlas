import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/screens/map_screen.dart';
import 'package:rideatlas/services/daily_analysis.dart';

TrackPoint _pt(double lat, double lon, {DateTime? time}) =>
    TrackPoint(latLng: LatLng(lat, lon), time: time);

void main() {
  group('buildTrackPolylines', () {
    test('keeps full track when only some points have timestamps', () {
      final day = DateTime.utc(2026, 8, 1, 10);
      final points = <TrackPoint>[
        for (var i = 0; i < 5; i++)
          _pt(41.0 + i * 0.001, 29.0, time: day.add(Duration(minutes: i))),
        for (var i = 5; i < 100; i++) _pt(41.0 + i * 0.001, 29.0),
      ];
      final days = splitIntoDays(points);
      expect(days, isNotEmpty);
      expect(
        days.fold<int>(0, (n, d) => n + d.points.length),
        lessThan(points.length),
      );

      final lines = buildTrackPolylines(points: points, days: days);
      expect(lines, hasLength(1));
      expect(lines.single.points, hasLength(points.length));
      expect(lines.single.color, const Color(0xFFE53935));
    });

    test('uses day colors when every point is timestamped', () {
      final day1 = DateTime.utc(2026, 8, 1, 10);
      final day2 = DateTime.utc(2026, 8, 2, 10);
      final points = <TrackPoint>[
        for (var i = 0; i < 10; i++)
          _pt(41.0 + i * 0.001, 29.0, time: day1.add(Duration(minutes: i))),
        for (var i = 0; i < 10; i++)
          _pt(41.1 + i * 0.001, 29.1, time: day2.add(Duration(minutes: i))),
      ];
      final days = splitIntoDays(points);
      expect(days, hasLength(2));

      final lines = buildTrackPolylines(points: points, days: days);
      expect(lines, hasLength(2));
      expect(lines[0].color, days[0].color);
      expect(lines[1].color, days[1].color);
    });

    test('falls back to full track when day filter matches nothing', () {
      final day = DateTime.utc(2026, 8, 1, 10);
      final points = <TrackPoint>[
        for (var i = 0; i < 20; i++)
          _pt(41.0 + i * 0.001, 29.0, time: day.add(Duration(minutes: i))),
      ];
      final days = splitIntoDays(points);
      expect(days, hasLength(1));

      final lines = buildTrackPolylines(
        points: points,
        days: days,
        // Stale filter from a previous multi-day view / renumbering.
        visibleDayNumbers: {99},
      );
      expect(lines, hasLength(1));
      expect(lines.single.points, hasLength(points.length));
    });

    test('untimed tracks stay a single red polyline', () {
      final points = <TrackPoint>[
        for (var i = 0; i < 30; i++) _pt(41.0 + i * 0.001, 29.0),
      ];
      final days = splitIntoDays(points);
      expect(days, isEmpty);

      final lines = buildTrackPolylines(points: points, days: days);
      expect(lines, hasLength(1));
      expect(lines.single.points, hasLength(30));
    });
  });
}
