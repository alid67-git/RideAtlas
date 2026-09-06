import 'package:rideatlas/flutter_test.dart';
import 'package:rideatlas/latlong.dart';
import 'package:rideatlas/services/track_display_loader.dart';

void main() {
  setUp(() => TrackDisplayCache.instance.clear());

  test('TrackDisplayCache stores and returns points', () {
    final key = TrackDisplayCache.key(
      routeId: 'r1',
      maxPoints: 1000,
      minSpacingMeters: 30,
      pointCount: 5000,
      fingerprint: 'abc',
    );
    final points = [LatLng(40, 29), LatLng(41, 30)];
    expect(TrackDisplayCache.instance.get(key), isNull);
    TrackDisplayCache.instance.put(key, points);
    expect(TrackDisplayCache.instance.get(key), points);
  });

  test('TrackDisplayCache evicts oldest when over capacity', () {
    for (var i = 0; i < 85; i++) {
      final key = TrackDisplayCache.key(
        routeId: 'r$i',
        maxPoints: 100,
        minSpacingMeters: 15,
        pointCount: i,
      );
      TrackDisplayCache.instance.put(key, [LatLng(0, 0), LatLng(1, 1)]);
    }
    expect(TrackDisplayCache.instance.length, lessThanOrEqualTo(80));
    // First keys should be gone.
    final first = TrackDisplayCache.key(
      routeId: 'r0',
      maxPoints: 100,
      minSpacingMeters: 15,
      pointCount: 0,
    );
    expect(TrackDisplayCache.instance.get(first), isNull);
  });
}
