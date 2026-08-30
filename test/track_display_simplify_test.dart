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
}
