import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/gpx_route.dart';
import 'package:rideatlas/services/map_camera_fit.dart';

GpxRoute _route({
  required double north,
  required double south,
  required double east,
  required double west,
}) {
  return GpxRoute(
    id: '$north-$south-$east-$west',
    name: 't',
    importedAt: DateTime.utc(2026, 1, 1),
    recordedAt: DateTime.utc(2026, 1, 1),
    distanceMeters: 1000,
    elevationGainMeters: 0,
    elevationLossMeters: 0,
    minElevation: null,
    maxElevation: null,
    durationSeconds: null,
    pointCount: 10,
    north: north,
    south: south,
    east: east,
    west: west,
  );
}

void main() {
  test('boundsForRoutes: one track uses that track only', () {
    final bounds = boundsForRoutes([
      _route(north: 41, south: 40, east: 30, west: 29),
    ]);
    expect(bounds, isNotNull);
    expect(bounds!.north, 41);
    expect(bounds.south, 40);
    expect(bounds.east, 30);
    expect(bounds.west, 29);
  });

  test('boundsForRoutes: many tracks union all', () {
    final bounds = boundsForRoutes([
      _route(north: 41, south: 40, east: 30, west: 29),
      _route(north: 42, south: 39, east: 31, west: 28),
    ]);
    expect(bounds, isNotNull);
    expect(bounds!.north, 42);
    expect(bounds.south, 39);
    expect(bounds.east, 31);
    expect(bounds.west, 28);
  });

  test('extendBoundsWithPoints adds live track', () {
    final base = boundsForRoutes([
      _route(north: 41, south: 40, east: 30, west: 29),
    ]);
    final extended = extendBoundsWithPoints(base, const [
      LatLng(39.5, 28.5),
      LatLng(39.6, 28.6),
    ]);
    expect(extended!.south, lessThan(40));
    expect(extended.west, lessThan(29));
  });
}
