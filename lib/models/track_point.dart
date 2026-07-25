import 'package:latlong2/latlong.dart';

/// A single point along a GPX track, with optional elevation and timestamp.
class TrackPoint {
  const TrackPoint({required this.latLng, this.elevation, this.time});

  final LatLng latLng;
  final double? elevation;
  final DateTime? time;
}
