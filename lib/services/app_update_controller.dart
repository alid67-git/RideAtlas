import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../build_info.dart';
import 'update_checker.dart';

/// Shared Android update state so home, recording, and info screens can all
/// show the same bottom "Güncelle" banner once a newer build is known.
class AppUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateInfo? available;
  bool dismissed = false;
  bool installing = false;
  bool _checking = false;
  bool _started = false;
  Timer? _poll;

  /// Bytes received / expected while [installing]. Null until the first chunk.
  (int received, int total)? downloadProgress;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get showBanner {
    if (!isSupported) return false;
    if (installing) return true;
    return available != null && !dismissed;
  }

  /// Idempotent: first check now, then every 60s and on resume. Safe to call
  /// from both home and record - the banner is the only offer (no dialog).
  void startPeriodicChecks() {
    if (!isSupported || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    check();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    if (!isSupported || _checking || available != null) return;
    _checking = true;
    try {
      final info = await checkForAndroidUpdate(kAppBuildLabel);
      if (info == null) return;
      available = info;
      notifyListeners();
    } finally {
      _checking = false;
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
    _poll?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
