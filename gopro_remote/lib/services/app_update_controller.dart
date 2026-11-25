import 'dart:async';

import 'package:flutter/foundation.dart';

import '../build_info.dart';
import 'update_checker.dart';

Duration delayUntilNextLocalNoon(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, 12);
  if (!now.isBefore(next)) {
    next = next.add(const Duration(days: 1));
  }
  return next.difference(now);
}

/// Shared Android update state (RideAtlas model, GoPro Remote APK).
class AppUpdateController extends ChangeNotifier {
  UpdateInfo? available;
  bool dismissed = false;
  bool installing = false;
  bool _checking = false;

  (int received, int total)? downloadProgress;

  Timer? _dailyNoonTimer;
  Future<void> Function()? _onUpdateFound;

  static final bool isSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isChecking => _checking;

  bool get showBanner {
    if (!isSupported) return false;
    if (installing) return true;
    return available != null && !dismissed;
  }

  void startDailyNoonChecks({Future<void> Function()? onUpdateFound}) {
    if (onUpdateFound != null) _onUpdateFound = onUpdateFound;
    _scheduleNextNoonCheck();
  }

  void _scheduleNextNoonCheck() {
    _dailyNoonTimer?.cancel();
    if (!isSupported) return;
    final delay = delayUntilNextLocalNoon(DateTime.now());
    _dailyNoonTimer = Timer(delay, () {
      unawaited(_onDailyNoon());
    });
  }

  Future<void> _onDailyNoon() async {
    try {
      await check(force: true);
      if (available != null && !installing) {
        if (dismissed) {
          dismissed = false;
          notifyListeners();
        }
        await _onUpdateFound?.call();
      }
    } finally {
      _scheduleNextNoonCheck();
    }
  }

  Future<void> check({bool force = false}) async {
    if (!isSupported || _checking) return;
    if (!force && available != null) return;
    await checkNow();
  }

  Future<AndroidUpdateProbeStatus> checkNow() async {
    if (!isSupported) return AndroidUpdateProbeStatus.failed;
    if (_checking) return AndroidUpdateProbeStatus.failed;
    _checking = true;
    notifyListeners();
    try {
      final result = await probeAndroidUpdate(kAppBuildLabel);
      if (result.status == AndroidUpdateProbeStatus.updateAvailable) {
        available = result.info;
        dismissed = false;
      }
      return result.status;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    notifyListeners();
  }

  void beginInstall() {
    if (installing) return;
    installing = true;
    downloadProgress = null;
    notifyListeners();
  }

  void reportDownloadProgress(int received, int total) {
    downloadProgress = (received, total);
    notifyListeners();
  }

  void endInstall({required bool success}) {
    installing = false;
    downloadProgress = null;
    if (success) dismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _dailyNoonTimer?.cancel();
    _dailyNoonTimer = null;
    super.dispose();
  }
}
