/// Persisted metadata for an imported GPX route. The raw GPX content itself
/// is stored separately (see [RouteRepository]), keyed by [id]; this record
/// only caches the summary stats so the route list can render instantly
/// without re-parsing every file.
class GpxRoute {
  const GpxRoute({
    required this.id,
    required this.name,
    required this.importedAt,
    required this.recordedAt,
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
    this.batteryStartPercent,
    this.batteryEndPercent,
  });

  final String id;
  final String name;

  /// When the file was imported / saved into RideAtlas.
  final DateTime importedAt;

  /// When the ride itself happened (first GPS timestamp on the track).
  /// Falls back to [importedAt] when the file has no point times.
  /// Route lists sort by this, newest first.
  final DateTime recordedAt;

  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final double? minElevation;
  final double? maxElevation;

  /// Wall-clock span from the first to the last GPS point - includes every
  /// stop and wait along the way. For actual moving/riding time, see
  /// [buildSpeedStats]'s `movingSeconds` - computed from point-to-point
  /// speed rather than cached here, since a gap-based estimate can't tell a
  /// genuine stop from a device that keeps logging points at rest.
  final int? durationSeconds;
  final int pointCount;
  final double north;
  final double south;
  final double east;
  final double west;

  /// Device battery percentage (0-100) when an in-app recording started/
  /// finished. Null for routes imported from a file, or if the platform
  /// couldn't report a battery level.
  final int? batteryStartPercent;
  final int? batteryEndPercent;

  double get distanceKm => distanceMeters / 1000;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  double? get averageSpeedKmh {
    final d = duration;
    if (d == null || d.inSeconds == 0) return null;
    return distanceKm / (d.inSeconds / 3600);
  }

  GpxRoute copyWith({String? name, DateTime? recordedAt}) {
    return GpxRoute(
      id: id,
      name: name ?? this.name,
      importedAt: importedAt,
      recordedAt: recordedAt ?? this.recordedAt,
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
      batteryStartPercent: batteryStartPercent,
      batteryEndPercent: batteryEndPercent,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'importedAt': importedAt.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
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
    'batteryStartPercent': batteryStartPercent,
    'batteryEndPercent': batteryEndPercent,
  };

  factory GpxRoute.fromJson(Map<String, dynamic> json) {
    final importedAt = DateTime.parse(json['importedAt'] as String);
    final recordedRaw = json['recordedAt'] as String?;
    return GpxRoute(
      id: json['id'] as String,
      name: json['name'] as String,
      importedAt: importedAt,
      // Pre-recordedAt builds: fall back to import time.
      recordedAt: recordedRaw != null
          ? DateTime.parse(recordedRaw)
          : importedAt,
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
      batteryStartPercent: json['batteryStartPercent'] as int?,
      batteryEndPercent: json['batteryEndPercent'] as int?,
    );
  }
}
