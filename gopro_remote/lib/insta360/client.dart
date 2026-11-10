import 'package:flutter/foundation.dart';

import 'models.dart';

/// Placeholder client for Insta360 X4+ (BLE / Wi‑Fi remote).
///
/// UI is wired now; real protocol work lands in a follow-up.
class Insta360Client extends ChangeNotifier {
  Insta360ConnectionState _state = Insta360ConnectionState.unsupported;
  Insta360ConnectionState get state => _state;

  String? _error;
  String? get error => _error;

  String? connectedName;
  Insta360CameraStatus status = const Insta360CameraStatus();

  bool get isConnected => _state == Insta360ConnectionState.connected;
  bool get isSessionRecording => status.encoding;
  bool get isSupported => false;

  Future<void> toggleRecording() async {
    _error = 'Insta360 X4+ kumandası yakında eklenecek.';
    _state = Insta360ConnectionState.unsupported;
    notifyListeners();
    throw StateError(_error!);
  }

  Future<void> toggleConnectSleep() async {
    _error = 'Insta360 X4+ bağlantısı yakında eklenecek.';
    _state = Insta360ConnectionState.unsupported;
    notifyListeners();
    throw StateError(_error!);
  }

  Future<void> cancelOperation() async {}
}
