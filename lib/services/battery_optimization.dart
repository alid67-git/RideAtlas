import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.rideatlas.app/battery');

/// Android-only. Many OEM skins (MIUI, ColorOS, OneUI, ...) throttle or
/// kill even a proper foreground service's GPS updates once the screen
/// turns off, unless the app is exempted from battery optimization - a
/// foreground service alone isn't always enough on these skins. A no-op
/// (returns true) everywhere else, where this isn't a concept.
Future<bool> isIgnoringBatteryOptimizations() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        true;
  } catch (_) {
    return true;
  }
}

/// Shows the system dialog letting the user exempt RideAtlas from battery
/// optimization, if it isn't already exempted. A no-op everywhere but
/// Android.
Future<void> requestIgnoreBatteryOptimizations() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  } catch (_) {
    // Best-effort: some OEMs block this intent entirely, in which case the
    // user still has the Settings app itself as a manual fallback.
  }
}
