import 'package:latlong2/latlong.dart';

/// Whether a [RoutePhoto] record holds a still photo or a video. Kept in the
/// same model/storage (name notwithstanding) since both are just "media
/// attached to a route" and share every other field.
enum RouteMediaType { photo, video }

/// A user-added photo or video attached to a route, optionally geotagged so
/// it can be shown as a marker on the map - either read from the file's own
/// EXIF GPS data (photos only; video containers don't have a reliably
/// readable equivalent across platforms) or picked manually on the map. The
/// raw bytes are stored separately (see `PhotoRepository`), keyed by [id];
/// this record only carries the small metadata needed to list/place it.
class RoutePhoto {
  const RoutePhoto({
    required this.id,
    required this.routeId,
    required this.addedAt,
    this.lat,
    this.lng,
    this.type = RouteMediaType.photo,
  });

  final String id;
  final String routeId;
  final DateTime addedAt;
  final double? lat;
  final double? lng;
  final RouteMediaType type;

  bool get hasLocation => lat != null && lng != null;
  bool get isVideo => type == RouteMediaType.video;

  LatLng? get latLng => hasLocation ? LatLng(lat!, lng!) : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'addedAt': addedAt.toIso8601String(),
    'lat': lat,
    'lng': lng,
    'type': type.name,
  };

  factory RoutePhoto.fromJson(Map<String, dynamic> json) => RoutePhoto(
    id: json['id'] as String,
    routeId: json['routeId'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    type: RouteMediaType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => RouteMediaType.photo,
    ),
  );
}
