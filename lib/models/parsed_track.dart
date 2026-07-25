import 'track_point.dart';
import 'waypoint.dart';

/// The result of parsing a track file (GPX or KML): the flattened track line
/// plus any named waypoints, ready to be drawn on the map or turned into
/// stats.
class ParsedTrack {
  const ParsedTrack({
    required this.points,
    required this.waypoints,
    required this.suggestedName,
  });

  final List<TrackPoint> points;
  final List<Waypoint> waypoints;
  final String? suggestedName;
}
