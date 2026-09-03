import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rideatlas/services/app_update_controller.dart';
import 'package:rideatlas/services/update_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('banner stays hidden until an update exists, then dismiss hides it', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ctrl = AppUpdateController();
    addTearDown(ctrl.dispose);

    expect(ctrl.showBanner, isFalse);

    ctrl.available = const UpdateInfo(
      version: 'v1.4.85 beta',
      downloadUrl: 'https://example.com/RideAtlas.apk',
      sizeBytes: 1,
    );
    expect(ctrl.showBanner, isTrue);

    ctrl.dismiss();
    expect(ctrl.dismissed, isTrue);
    expect(ctrl.showBanner, isFalse);
  });

  test('startPeriodicChecks is a no-op off Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final ctrl = AppUpdateController();
    addTearDown(ctrl.dispose);
    ctrl.startPeriodicChecks();
    expect(ctrl.showBanner, isFalse);
  });
}
