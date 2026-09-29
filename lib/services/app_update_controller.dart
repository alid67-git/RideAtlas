import 'dart:async';

import 'package:flutter/foundation.dart';

import '../build_info.dart';
import 'update_checker.dart';

/// Delay from [now] until the next local 12:00 (today if still morning,
/// otherwise tomorrow). Exposed for unit tests of the daily noon schedule.
Duration delayUntilNextLocalNoon(DateTime now) {
  var next = DateTime(now.year, now.month, now.day, 12);
  if (!now.isBefore(next)) {
    next = next.add(const Duration(days: 1));
  }
  return next.difference(now);
}

/// Shared Android update state so home, recording, and info screens can all
/// show the same "Güncelle" offer once a newer build is known.
///
/// Also owns the "app left open overnight" schedule: once
/// [startDailyNoonChecks] has been called, a local-noon timer re-probes
/// GitHub every day and notifies [onUpdateFound] so a silent install can
/// start without the rider reopening the app.
class AppUpdateController extends ChangeNotifier {
  UpdateInfo? available;
  bool dismissed = false;
  bool installing = false;
  bool _checking = false;

  /// Bytes received / expected while [installing]. Null until the first chunk.
  (int received, int total)? downloadProgress;

  Timer? _dailyNoonTimer;
  Future<void> Function()? _onUpdateFound;

  static final bool isSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True while a GitHub probe is in flight (silent or Settings-triggered).
  bool get isChecking => _checking;

  bool get showBanner {
    if (!isSupported) return false;
    if (installing) return true;
    return available != null && !dismissed;
  }

  /// Arms (or rearms) the every-day-at-local-noon probe. Idempotent - safe
  /// to call once from app bootstrap. [onUpdateFound] runs after a noon
  /// check discovers a newer build (typically to kick off a silent install).
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
      // Force a fresh probe even if an earlier offer was dismissed - a
      // long-running recording session shouldn't miss a build that landed
      // overnight.
      await check(force: true);
      if (available != null && !installing) {
        if (dismissed) {
          dismissed = false;
          notifyListeners();
        }
        await _onUpdateFound?.call();
      }
    } finally {
      // Always re-arm for tomorrow, even if today's probe failed offline.
      _scheduleNextNoonCheck();
    }
  }

  /// Probes GitHub for a newer APK. When [force] is false (default), skips
  /// if an update is already known - the home/record launch path. Noon
  /// checks pass [force] so a dismissed offer can be revived.
  Future<void> check({bool force = false}) async {
    if (!isSupported || _checking) return;
    if (!force && available != null) return;
    await checkNow();
  }

  /// Always hits the network (unless a probe is already running). Used by
  /// Settings so the rider can ask "is there an update?" and get a clear
  /// up-to-date / available / failed answer. Revives a previously dismissed
  /// offer when a newer build is found.
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
