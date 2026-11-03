import 'dart:math' show max;

/// Indoor / urban GPS jitters inside its own reported accuracy circle.
/// Treat that wander as "still", not a ride: it is what turned a phone
/// sitting at home into kilometres of track and a 70 km/h "max speed"
/// (a ~40 m hop in 2 s).
///
/// [accuracyMeters] ≤ 0 is treated as unknown; use [unknownMeters] so a
/// missing figure does not disable the gate.
double gpsNoiseRadiusMeters(
  double accuracyMeters, {
  double unknownMeters = 15,
}) {
  if (!accuracyMeters.isFinite || accuracyMeters <= 0) return unknownMeters;
  return accuracyMeters;
}

/// True when [meters] is still GPS wander, not a ride.
///
/// Fused location often reports 5–10 m accuracy indoors while the fix
/// actually jumps 10–25 m (v1.4.127 still let ~100 m and a 10.8 km/h
/// "max" through in six minutes at home). Gate is the larger of a 25 m
/// floor and 2× the reported accuracy.
bool isGpsHopWithinNoise({
  required double meters,
  required double accuracyMeters,
  double minMeters = 25,
}) {
  if (!meters.isFinite || meters < 0) return true;
  final gate = max(minMeters, 2 * gpsNoiseRadiusMeters(accuracyMeters));
  return meters <= gate;
}

/// Auto-pause should only clear on a hop that is clearly outside the
/// uncertainty, not a 20 m indoor reflection. Outdoor walking (accuracy
/// ~8 m) still resumes at [minMeters] (20 m).
bool isGpsHopARealMoveAway({
  required double meters,
  required double accuracyMeters,
  double minMeters = 20,
}) {
  if (!meters.isFinite || meters < 0) return false;
  final gate = max(minMeters, 2 * gpsNoiseRadiusMeters(accuracyMeters));
  return meters >= gate;
}
