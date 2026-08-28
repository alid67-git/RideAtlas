import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Wide-map anchor when GPS is unknown. Must not be a real city — Istanbul
/// was the old default and confused riders who opened the app elsewhere.
const kUnknownLocationMapCenter = LatLng(20.0, 0.0);

/// Reject cached fixes the OS hands to [Geolocator.getPositionStream] before
/// a fresh read (e.g. last-known from another country).
const _maxAcceptedPositionAge = Duration(minutes: 3);

bool isAcceptableLivePosition(Position pos) {
  return DateTime.now().difference(pos.timestamp) <= _maxAcceptedPositionAge;
}

/// One-shot read for the locate-me button — not the stale stream cache.
Future<Position?> fetchFreshDevicePosition() async {
  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (isAcceptableLivePosition(pos)) return pos;
  } catch (_) {}

  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && isAcceptableLivePosition(last)) return last;
  } catch (_) {}

  return null;
}
