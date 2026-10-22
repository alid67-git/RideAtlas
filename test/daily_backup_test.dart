import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/daily_backup.dart';

void main() {
  group('daily backup day slicing', () {
    final day1 = DateTime(2026, 10, 12);
    final day2 = DateTime(2026, 10, 13);

    List<TrackPoint> sample() => [
      TrackPoint(
        latLng: const LatLng(41.0, 29.0),
        time: DateTime(2026, 10, 12, 8, 0),
      ),
      TrackPoint(
        latLng: const LatLng(41.01, 29.01),
        time: DateTime(2026, 10, 12, 20, 0),
      ),
      TrackPoint(
        latLng: const LatLng(41.02, 29.02),
        time: DateTime(2026, 10, 13, 1, 0),
      ),
      TrackPoint(
        latLng: const LatLng(41.03, 29.03),
        // timeless - ignored for day split
      ),
    ];

    test('pointsForLocalDay keeps only that calendar day', () {
      final points = sample();
      final d1 = pointsForLocalDay(points, day1);
      final d2 = pointsForLocalDay(points, day2);
      expect(d1.length, 2);
      expect(d2.length, 1);
      expect(d1.first.latLng.latitude, 41.0);
      expect(d2.single.latLng.latitude, 41.02);
    });

    test('buildDayBackupGpx embeds only that day and names the file day', () {
      final gpx = buildDayBackupGpx(allPoints: sample(), day: day1)!;
      expect(gpx, contains('RideAtlas 2026-10-12'));
      expect(gpx, contains('41.0'));
      expect(gpx, contains('41.01'));
      expect(gpx, isNot(contains('41.02')));
      expect(dayBackupFileName(day1), 'RideAtlas_2026-10-12.gpx');
    });

    test('buildDayBackupGpx returns null when day empty', () {
      expect(
        buildDayBackupGpx(allPoints: sample(), day: DateTime(2026, 1, 1)),
        isNull,
      );
    });
  });
}
