import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/models/waypoint.dart';
import 'package:rideatlas/services/day_export.dart';
import 'package:rideatlas/services/track_export_actions.dart';
import 'package:rideatlas/services/track_io.dart';

void main() {
  final day1 = DateTime(2026, 10, 12);
  final day2 = DateTime(2026, 10, 13);

  List<TrackPoint> samplePoints() => [
        TrackPoint(
          latLng: const LatLng(41.0, 29.0),
          time: DateTime(2026, 10, 12, 8, 0),
        ),
        TrackPoint(
          latLng: const LatLng(41.01, 29.01),
          time: DateTime(2026, 10, 12, 18, 0),
        ),
        TrackPoint(
          latLng: const LatLng(41.02, 29.02),
          time: DateTime(2026, 10, 13, 9, 0),
        ),
      ];

  group('waypointsForLocalDay', () {
    test('keeps waypoint nearest to that day\'s track', () {
      final points = samplePoints();
      final wDay1 = Waypoint(
        latLng: const LatLng(41.005, 29.005),
        name: 'note-day1',
      );
      final wDay2 = Waypoint(
        latLng: const LatLng(41.021, 29.021),
        name: 'note-day2',
      );
      final d1 = waypointsForLocalDay(
        waypoints: [wDay1, wDay2],
        allPoints: points,
        day: day1,
      );
      final d2 = waypointsForLocalDay(
        waypoints: [wDay1, wDay2],
        allPoints: points,
        day: day2,
      );
      expect(d1.map((w) => w.name), ['note-day1']);
      expect(d2.map((w) => w.name), ['note-day2']);
    });
  });

  group('buildDayTrackExport', () {
    test('embeds only that day\'s points', () {
      final export = buildDayTrackExport(
        allPoints: samplePoints(),
        waypoints: const [],
        day: day1,
        format: TrackFormat.gpx,
      )!;
      final text = String.fromCharCodes(export.bytes);
      expect(text, contains('41.0'));
      expect(text, contains('41.01'));
      expect(text, isNot(contains('41.02')));
    });
  });

  group('preparePlanExportFiles', () {
    test('selected days produces one file per day', () {
      final plan = DayExportPlan(
        scope: DayExportScope.selectedDays,
        destination: DayExportDestination.share,
        selectedDays: [day1, day2],
      );
      final files = preparePlanExportFiles(
        plan: plan,
        routeName: 'Tour',
        points: samplePoints(),
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      expect(files.length, 2);
      expect(files[0].baseName, 'Tour_2026-10-12');
      expect(files[1].baseName, 'Tour_2026-10-13');
    });

    test('full route produces a single file', () {
      final plan = const DayExportPlan(
        scope: DayExportScope.fullRoute,
        destination: DayExportDestination.share,
        selectedDays: [],
      );
      final files = preparePlanExportFiles(
        plan: plan,
        routeName: 'Tour',
        points: samplePoints(),
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      expect(files.length, 1);
      expect(files.single.baseName, 'Tour');
    });

    test('selecting only day 1 exports that day alone', () {
      final plan = DayExportPlan(
        scope: DayExportScope.selectedDays,
        destination: DayExportDestination.folder,
        selectedDays: [day1],
      );
      final files = preparePlanExportFiles(
        plan: plan,
        routeName: 'Tour',
        points: samplePoints(),
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      expect(files.length, 1);
      final text = String.fromCharCodes(files.single.export.bytes);
      expect(text, isNot(contains('41.02')));
    });
  });
}
