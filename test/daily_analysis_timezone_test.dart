import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/daily_analysis.dart';

TrackPoint _pt(double lat, double lon, {DateTime? time}) =>
    TrackPoint(latLng: LatLng(lat, lon), time: time);

void main() {
  group('calendarDayLocal / splitIntoDays timezone', () {
    test('calendarDayLocal uses device-local Y/M/D', () {
      final utc = DateTime.utc(2026, 8, 27, 22, 30);
      final day = calendarDayLocal(utc);
      final local = utc.toLocal();
      expect(day.year, local.year);
      expect(day.month, local.month);
      expect(day.day, local.day);
      expect(day.isUtc, isFalse);
    });

    test(
      'late-evening UTC points land on the next local calendar day '
      'when the device is east of UTC',
      () {
        // Skip on hosts whose local offset is 0 - the bug is invisible
        // there (UTC calendar day == local calendar day).
        if (DateTime.now().timeZoneOffset <= Duration.zero) {
          return;
        }
        // 22:30 UTC on the 27th is already the 28th locally for any
        // positive offset (Turkey UTC+3 → 01:30 on the 28th).
        final lateUtc = DateTime.utc(2026, 8, 27, 22, 30);
        final morningLocalDay = DateTime.utc(2026, 8, 28, 6);
        final points = <TrackPoint>[
          _pt(41.0, 29.0, time: lateUtc),
          _pt(41.01, 29.01, time: lateUtc.add(const Duration(minutes: 10))),
          _pt(41.02, 29.02, time: morningLocalDay),
          _pt(41.03, 29.03, time: morningLocalDay.add(const Duration(hours: 1))),
        ];
        final days = splitIntoDays(points);
        // Both groups share the same local calendar day (the 28th).
        expect(days, hasLength(1));
        expect(days.single.points, hasLength(4));
        expect(days.single.date.day, lateUtc.toLocal().day);
      },
    );

    test('same UTC calendar day still splits across local midnight', () {
      if (DateTime.now().timeZoneOffset <= Duration.zero) {
        return;
      }
      // 20:00 UTC (= 23:00 TR) on the 27th and 22:00 UTC (= 01:00 TR on
      // the 28th) share a UTC date but not a local one.
      final evening = DateTime.utc(2026, 8, 27, 20);
      final afterMidnight = DateTime.utc(2026, 8, 27, 22);
      final points = <TrackPoint>[
        _pt(41.0, 29.0, time: evening),
        _pt(41.01, 29.01, time: evening.add(const Duration(minutes: 30))),
        _pt(41.02, 29.02, time: afterMidnight),
        _pt(41.03, 29.03, time: afterMidnight.add(const Duration(minutes: 30))),
      ];
      final days = splitIntoDays(points);
      expect(days, hasLength(2));
      expect(days[0].points, hasLength(2));
      expect(days[1].points, hasLength(2));
      // Distances must not bleed across the local midnight boundary.
      expect(days[0].distanceKm, greaterThan(0));
      expect(days[1].distanceKm, greaterThan(0));
      final total = days[0].distanceKm + days[1].distanceKm;
      // Cross-midnight gap between evening and afterMidnight is NOT
      // counted into either day (day buckets only sum consecutive points
      // inside the same day) - so total day distance is less than a
      // single end-to-end sum that would include the overnight jump.
      final endToEnd = const Distance().as(
            LengthUnit.Kilometer,
            points.first.latLng,
            points.last.latLng,
          );
      expect(total, lessThan(endToEnd));
    });
  });
}
