/// Persisted metadata for an imported GPX route. The raw GPX content itself
/// is stored separately (see [RouteRepository]), keyed by [id]; this record
/// only caches the summary stats so the route list can render instantly
/// without re-parsing every file.
class GpxRoute {
  const GpxRoute({
    required this.id,
    required this.name,
    required this.importedAt,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
    required this.minElevation,
    required this.maxElevation,
    required this.durationSeconds,
    required this.pointCount,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final String id;
  final String name;
  final DateTime importedAt;
  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double? minElevation;
  final double? maxElevation;
  final int? durationSeconds;
  final int pointCount;
  final double north;
  final double south;
  final double east;
  final double west;

  double get distanceKm => distanceMeters / 1000;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  double? get averageSpeedKmh {
    final d = duration;
    if (d == null || d.inSeconds == 0) return null;
    return distanceKm / (d.inSeconds / 3600);
  }

  GpxRoute copyWith({String? name}) {
    return GpxRoute(
      id: id,
      name: name ?? this.name,
      importedAt: importedAt,
      distanceMeters: distanceMeters,
      elevationGainMeters: elevationGainMeters,
      elevationLossMeters: elevationLossMeters,
      minElevation: minElevation,
      maxElevation: maxElevation,
      durationSeconds: durationSeconds,
      pointCount: pointCount,
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'importedAt': importedAt.toIso8601String(),
    'distanceMeters': distanceMeters,
    'elevationGainMeters': elevationGainMeters,
    'elevationLossMeters': elevationLossMeters,
    'minElevation': minElevation,
    'maxElevation': maxElevation,
    'durationSeconds': durationSeconds,
    'pointCount': pointCount,
    'north': north,
    'south': south,
    'east': east,
    'west': west,
  };

  factory GpxRoute.fromJson(Map<String, dynamic> json) {
    return GpxRoute(
      id: json['id'] as String,
      name: json['name'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      elevationGainMeters: (json['elevationGainMeters'] as num).toDouble(),
      elevationLossMeters: (json['elevationLossMeters'] as num).toDouble(),
      minElevation: (json['minElevation'] as num?)?.toDouble(),
      maxElevation: (json['maxElevation'] as num?)?.toDouble(),
      durationSeconds: json['durationSeconds'] as int?,
      pointCount: json['pointCount'] as int,
      north: (json['north'] as num).toDouble(),
      south: (json['south'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
      west: (json['west'] as num).toDouble(),
    );
  }
}
