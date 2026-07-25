import 'package:latlong2/latlong.dart';

/// A named point of interest from a GPX file (`<wpt>`).
class Waypoint {
  const Waypoint({required this.latLng, this.name, this.description});

  final LatLng latLng;
  final String? name;
  final String? description;
}
