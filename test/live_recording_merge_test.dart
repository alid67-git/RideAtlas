import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/live_recording_merge.dart';

TrackPoint _pt(DateTime time, double lat, double lng) => TrackPoint(
      latLng: LatLng(lat, lng),
      time: time,
    );

void main() {
  test('fills missing days and keeps other live days', () {
    final day1 = [
      _pt(DateTime(2026, 11, 17, 9), 7.88, 98.38),
      _pt(DateTime(2026, 11, 17, 12), 7.90, 98.40),
    ];
    final day3Live = [
      _pt(DateTime(2026, 11, 19, 8), 8.00, 98.50),
      _pt(DateTime(2026, 11, 19, 10), 8.02, 98.52),
    ];
    final importedDay2 = [
      _pt(DateTime(2026, 11, 18, 9), 7.95, 98.45),
      _pt(DateTime(2026, 11, 18, 15), 7.98, 98.48),
    ];

    final result = mergePointsReplacingImportedDays(
      existing: [...day1, ...day3Live],
      incoming: importedDay2,
    );

    expect(result.replacedDays, [DateTime(2026, 11, 18)]);
    expect(result.addedPointCount, 2);
    expect(result.points.map((p) => p.time!.day).toList(), [17, 17, 18, 18, 19, 19]);
  });

  test('replaces an overlapping day instead of duplicating it', () {
    final live = [
      _pt(DateTime(2026, 11, 18, 8), 7.0, 98.0),
      _pt(DateTime(2026, 11, 18, 9), 7.01, 98.01),
      _pt(DateTime(2026, 11, 19, 8), 8.0, 99.0),
    ];
    final replacement = [
      _pt(DateTime(2026, 11, 18, 10), 7.5, 98.5),
      _pt(DateTime(2026, 11, 18, 14), 7.6, 98.6),
    ];

    final result = mergePointsReplacingImportedDays(
      existing: live,
      incoming: replacement,
    );

    expect(result.replacedDays, [DateTime(2026, 11, 18)]);
    final day18 = [
      for (final p in result.points)
        if (p.time!.day == 18) p.latLng.latitude,
    ];
    expect(day18, [7.5, 7.6]);
    expect(result.points.where((p) => p.time!.day == 19), hasLength(1));
  });

  test('no-op when import has no timestamps', () {
    final live = [_pt(DateTime(2026, 11, 18, 8), 7.0, 98.0)];
    final result = mergePointsReplacingImportedDays(
      existing: live,
      incoming: [const TrackPoint(latLng: LatLng(1, 2))],
    );
    expect(result.replacedDays, isEmpty);
    expect(result.addedPointCount, 0);
    expect(result.points, hasLength(1));
    expect(result.points.single.latLng, const LatLng(7.0, 98.0));
  });
}
