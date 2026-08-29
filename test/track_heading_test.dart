import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/services/track_heading.dart';

void main() {
  test('headingFromRecentTrackPoints: northbound ~0°', () {
    final heading = headingFromRecentTrackPoints(const [
      LatLng(40.0, 29.0),
      LatLng(40.001, 29.0),
      LatLng(40.002, 29.0),
    ]);
    expect(heading, isNotNull);
    expect(heading!, closeTo(0, 5));
  });

  test('headingFromRecentTrackPoints: eastbound ~90°', () {
    final heading = headingFromRecentTrackPoints(const [
      LatLng(40.0, 29.0),
      LatLng(40.0, 29.001),
      LatLng(40.0, 29.002),
    ]);
    expect(heading, isNotNull);
    expect(heading!, closeTo(90, 5));
  });

  test('headingFromRecentTrackPoints: too close returns null', () {
    final heading = headingFromRecentTrackPoints(const [
      LatLng(40.0, 29.0),
      LatLng(40.0, 29.0),
    ]);
    expect(heading, isNull);
  });

  test('headingFromRecentTrackPoints: needs at least two points', () {
    expect(headingFromRecentTrackPoints(const [LatLng(40.0, 29.0)]), isNull);
  });
}
