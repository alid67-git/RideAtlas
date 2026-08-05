import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.rideatlas.app/satellites');

/// Android-only. Returns the number of GPS/GNSS satellites currently used
/// in the position fix (see GnssSatelliteTracker.kt), or null if unknown -
/// no reading yet, unsupported Android version, or any other platform.
Future<int?> currentSatelliteCount() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await _channel.invokeMethod<int>('getSatelliteCount');
  } catch (_) {
    return null;
  }
}
