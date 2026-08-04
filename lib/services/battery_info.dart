import 'package:battery_plus/battery_plus.dart';

final _battery = Battery();

/// Current battery level (0-100), or null if unavailable on this platform
/// (desktop/Linux builds and some browsers don't expose one) or the read
/// simply fails - this is best-effort context for a ride, never something
/// worth blocking or erroring the recording flow over.
Future<int?> currentBatteryPercent() async {
  try {
    final level = await _battery.batteryLevel;
    return level >= 0 ? level : null;
  } catch (_) {
    return null;
  }
}
