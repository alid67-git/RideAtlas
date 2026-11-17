import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/driven_path.dart';

TrackPoint _pt(double lat, double lon, DateTime time) =>
    TrackPoint(latLng: LatLng(lat, lon), time: time);

void main() {
  group('drivenDistanceMeters', () {
    test('counts a clear driving hop', () {
      final t0 = DateTime.utc(2026, 11, 16, 10);
      // ~1.1 km in 90 s ≈ 44 km/h (under 2 km continuous-gap cap)
      final points = [
        _pt(7.9, 98.3, t0),
        _pt(7.91, 98.3, t0.add(const Duration(seconds: 90))),
      ];
      final m = drivenDistanceMeters(points);
      expect(m, greaterThan(900));
      expect(m, lessThan(1400));
    });

    test('ignores near-stationary GPS crawl', () {
      final t0 = DateTime.utc(2026, 11, 16, 10);
      // ~80 m in 5 min ≈ 1 km/h — below stationary floor
      final points = [
        _pt(7.9, 98.3, t0),
        _pt(7.9007, 98.3, t0.add(const Duration(minutes: 5))),
        _pt(7.9014, 98.3, t0.add(const Duration(minutes: 10))),
      ];
      expect(drivenDistanceMeters(points), 0);
    });

    test('ignores teleport jumps', () {
      final t0 = DateTime.utc(2026, 11, 16, 10);
      final points = [
        _pt(7.9, 98.3, t0),
        // ~50 km in 1 min → jump
        _pt(8.35, 98.3, t0.add(const Duration(minutes: 1))),
      ];
      expect(drivenDistanceMeters(points), 0);
    });
  });
}
