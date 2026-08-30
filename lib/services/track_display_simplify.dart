import 'package:latlong2/latlong.dart';

/// Max vertices drawn on the route map. An 8-day GPX at 1–2 s can be
/// 50k–200k points; painting all of them on every pan/pinch freezes the UI.
const kMapDisplayMaxPoints = 8000;

const _distance = Distance();

/// Drops redundant GPS vertices for **display only** (analysis/export keep
/// the full list). Always keeps the first and last point.
List<LatLng> latLngsForMapDisplay(
  List<LatLng> points, {
  int maxPoints = kMapDisplayMaxPoints,
  double minSpacingMeters = 15,
}) {
  if (points.length <= 2) return List<LatLng>.from(points);
  if (points.length <= maxPoints && minSpacingMeters <= 0) {
    return List<LatLng>.from(points);
  }

  final spaced = <LatLng>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    if (_distance.as(LengthUnit.Meter, spaced.last, p) >= minSpacingMeters) {
      spaced.add(p);
    }
  }
  if (spaced.last != points.last) spaced.add(points.last);

  if (spaced.length <= maxPoints) return spaced;

  final step = (spaced.length / maxPoints).ceil();
  final out = <LatLng>[spaced.first];
  for (var i = step; i < spaced.length - 1; i += step) {
    out.add(spaced[i]);
  }
  if (out.last != spaced.last) out.add(spaced.last);
  return out;
}
