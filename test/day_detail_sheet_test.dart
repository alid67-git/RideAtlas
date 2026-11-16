import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/daily_analysis.dart';
import 'package:rideatlas/widgets/day_detail_sheet.dart';

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
}
