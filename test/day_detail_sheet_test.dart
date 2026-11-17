import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/daily_analysis.dart';
import 'package:rideatlas/widgets/day_detail_sheet.dart';

DayStats _dayAt(int dayNumber, LatLng mid) {
  return DayStats(
    dayNumber: dayNumber,
    date: DateTime(2026, 11, dayNumber),
    points: [
      TrackPoint(latLng: mid, time: DateTime(2026, 11, dayNumber, 10)),
      TrackPoint(
        latLng: LatLng(mid.latitude + 0.00001, mid.longitude),
        time: DateTime(2026, 11, dayNumber, 11),
      ),
      TrackPoint(
        latLng: LatLng(mid.latitude + 0.00002, mid.longitude),
        time: DateTime(2026, 11, dayNumber, 12),
      ),
    ],
    color: colorForDay(dayNumber - 1),
    distanceKm: 1,
    elevationGainM: 0,
    elevationLossM: 0,
    maxElevation: null,
    minElevation: null,
    ridingDuration: const Duration(hours: 1),
    restDuration: Duration.zero,
    countries: const [],
  );
}

void main() {
  test('dayLabelAnchor uses the middle point of the day', () {
    final day = DateTime(2026, 11, 10);
    final points = [
      for (var i = 0; i < 5; i++)
        TrackPoint(
          latLng: LatLng(41.0 + i * 0.01, 29.0),
          time: DateTime(2026, 11, 10, 8 + i),
        ),
    ];
    final days = splitIntoDays(points);
    expect(days, hasLength(1));
    expect(dayLabelAnchor(days.single), points[2].latLng);
    expect(days.single.date, day);
  });

  test('dayLabelStackOffsets cascades near midpoints diagonally', () {
    const shared = LatLng(7.88, 98.39);
    final days = [
      _dayAt(3, shared),
      _dayAt(4, LatLng(shared.latitude + 0.0002, shared.longitude)),
      _dayAt(6, LatLng(shared.latitude - 0.0001, shared.longitude + 0.0001)),
      _dayAt(5, const LatLng(8.05, 98.30)), // far — no offset
    ];
    final offsets = dayLabelStackOffsets(days);
    expect(offsets, hasLength(4));
    expect(offsets[0], Offset.zero); // day 3, first in cluster
    expect(offsets[1], const Offset(kDayLabelStackStepX, kDayLabelStackStepY));
    expect(
      offsets[2],
      const Offset(2 * kDayLabelStackStepX, 2 * kDayLabelStackStepY),
    );
    expect(offsets[3], Offset.zero); // distant day 5
  });

  test('dayLabelStackOffsets leaves far-apart days unmoved', () {
    final days = [
      _dayAt(1, const LatLng(10, 100)),
      _dayAt(2, const LatLng(11, 101)),
    ];
    expect(dayLabelStackOffsets(days), everyElement(Offset.zero));
  });
}
