import 'package:latlong2/latlong.dart';

/// A user-added photo attached to a route, optionally geotagged (from the
/// photo's own EXIF GPS data) so it can be shown as a marker on the map. The
/// raw image bytes are stored separately (see `PhotoRepository`), keyed by
/// [id]; this record only carries the small metadata needed to list/place it.
class RoutePhoto {
  const RoutePhoto({
    required this.id,
    required this.routeId,
    required this.addedAt,
    this.lat,
    this.lng,
  });

  final String id;
  final String routeId;
  final DateTime addedAt;
  final double? lat;
  final double? lng;

  bool get hasLocation => lat != null && lng != null;

  LatLng? get latLng => hasLocation ? LatLng(lat!, lng!) : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'addedAt': addedAt.toIso8601String(),
    'lat': lat,
    'lng': lng,
  };

  factory RoutePhoto.fromJson(Map<String, dynamic> json) => RoutePhoto(
    id: json['id'] as String,
    routeId: json['routeId'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
  );
}
