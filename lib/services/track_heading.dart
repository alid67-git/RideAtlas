import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Course-up heading from the recent end of a track (old → new).
///
/// Uses the last up-to-three points so a single noisy GPS hop doesn't
/// dominate: bearing from [n-3] (or [n-2]) to the tip [n-1]. Returns null
/// when points are missing or too close to infer a direction.
double? headingFromRecentTrackPoints(
  List<LatLng> points, {
  double minDistanceMeters = 2,
}) {
  if (points.length < 2) return null;
  final tip = points.last;
  final from = points.length >= 3 ? points[points.length - 3] : points[points.length - 2];
  var distance = Geolocator.distanceBetween(
    from.latitude,
    from.longitude,
    tip.latitude,
    tip.longitude,
  );
  var origin = from;
  if (distance < minDistanceMeters && points.length >= 2) {
    origin = points[points.length - 2];
    distance = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      tip.latitude,
      tip.longitude,
    );
  }
  if (distance < 1) return null;
  final bearing = Geolocator.bearingBetween(
    origin.latitude,
    origin.longitude,
    tip.latitude,
    tip.longitude,
  );
  if (!bearing.isFinite) return null;
  return (bearing % 360 + 360) % 360;
}

/// flutter_map camera rotation that puts [headingDegrees] at the **top**
/// of the screen (travel up, trail behind / down).
///
/// [MapController.rotate] / [MapController.moveAndRotate] are clockwise.
/// Passing the heading itself rotates the wrong way: travel points down
/// and older points sit at the top. Same sign as Android Auto's
/// `canvas.rotate(-heading)`.
double courseUpMapRotation(double headingDegrees) => -headingDegrees;
