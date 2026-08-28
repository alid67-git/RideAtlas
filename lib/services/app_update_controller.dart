import 'package:flutter/foundation.dart';

import '../build_info.dart';
import 'update_checker.dart';

/// Shared Android update state so home, recording, and info screens can all
/// show the same "Güncelle" offer once a newer build is known.
class AppUpdateController extends ChangeNotifier {
  UpdateInfo? available;
  bool dismissed = false;
  bool installing = false;
  bool _checking = false;

  /// Bytes received / expected while [installing]. Null until the first chunk.
  (int received, int total)? downloadProgress;

  static final bool isSupported =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get showBanner {
    if (!isSupported) return false;
    if (installing) return true;
    return available != null && !dismissed;
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
}
