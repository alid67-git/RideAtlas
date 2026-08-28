import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _dailyModeKey = 'daily_mode_enabled';
const _dailySessionDayKey = 'daily_mode_session_day';

const _nativePrefsChannel = 'com.rideatlas.app/daily_mode';

/// Optional "Günlük mod": when on, opening the app silently resumes or
/// starts today's recording (no confirm dialogs), and each local calendar
/// day becomes its own saved ride. Survives battery death via the existing
/// native session file + auto-start on the next open.
///
/// The enabled flag is also mirrored to Android SharedPreferences so a
/// BOOT_COMPLETED receiver can relaunch the app without waiting for a
/// manual tap.
class DailyModeController extends ChangeNotifier {
  bool _enabled = false;
  bool get enabled => _enabled;

  /// Local calendar day (`yyyy-MM-dd`) the current/last daily session was
  /// started for - used to detect midnight rollover and cross-day restore.
  String? _sessionDay;
  String? get sessionDay => _sessionDay;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    _enabled = box.get(_dailyModeKey) == '1';
    _sessionDay = box.get(_dailySessionDayKey);
    notifyListeners();
    // Keep native boot flag in sync with Hive (in case prefs were cleared).
    if (isSupported) await _mirrorNative(_enabled);
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_dailyModeKey, enabled ? '1' : '0');
    if (!enabled) {
      _sessionDay = null;
      await box.delete(_dailySessionDayKey);
    }
    if (isSupported) await _mirrorNative(enabled);
  }

  Future<void> setSessionDay(String? dayKey) async {
    _sessionDay = dayKey;
    final box = await Hive.openBox<String>(_metaBoxName);
    if (dayKey == null) {
      await box.delete(_dailySessionDayKey);
    } else {
      await box.put(_dailySessionDayKey, dayKey);
    }
    notifyListeners();
  }

  /// `yyyy-MM-dd` in the device's local timezone.
  static String dayKey([DateTime? when]) {
    final local = (when ?? DateTime.now()).toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<void> _mirrorNative(bool enabled) async {
    try {
      await const MethodChannel(_nativePrefsChannel).invokeMethod<void>(
        'setEnabled',
        enabled,
      );
    } catch (_) {
      // Channel missing in tests / older APKs.
    }
  }
}
