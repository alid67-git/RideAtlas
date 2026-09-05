import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/services/track_display_simplify.dart';

void main() {
  test('latLngsForMapDisplay keeps first and last', () {
    final points = [
      for (var i = 0; i < 20000; i++) LatLng(40.0 + i * 0.00001, 29.0),
    ];
    final out = latLngsForMapDisplay(points);
    expect(out.first, points.first);
    expect(out.last, points.last);
    expect(out.length, lessThanOrEqualTo(kMapDisplayMaxPoints + 2));
    expect(out.length, lessThan(points.length));
  });

  test('latLngsForMapDisplay leaves short tracks intact', () {
    final points = [
      for (var i = 0; i < 20; i++) LatLng(41.0 + i * 0.001, 29.0),
    ];
    final out = latLngsForMapDisplay(points);
    expect(out, hasLength(20));
  });

  test('mapDisplayBudget tightens as route count grows', () {
    expect(mapDisplayBudget(1).maxPoints, kMapDisplayMaxPoints);
    expect(mapDisplayBudget(10).maxPoints, lessThan(mapDisplayBudget(3).maxPoints));
    expect(mapDisplayBudget(30).maxPoints, lessThan(mapDisplayBudget(10).maxPoints));
  });

  test('findNearestTrackHit samples and rejects distant tracks', () {
    final near = [
      for (var i = 0; i < 2000; i++) LatLng(40.0 + i * 0.00001, 29.0),
    ];
    final far = [
      for (var i = 0; i < 2000; i++) LatLng(50.0 + i * 0.00001, 10.0),
    ];
    final hit = findNearestTrackHit(
      tap: near[100],
      zoom: 14,
      tracks: [
        (id: 'far', name: 'Far', points: far),
        (id: 'near', name: 'Near', points: near),
      ],
    );
    expect(hit, isNotNull);
    expect(hit!.id, 'near');
  });
}
