import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A track file the OS handed us via Android "Open with" / share sheet
/// (ACTION_VIEW / ACTION_SEND). [bytes] is the full file contents already
/// read by MainActivity so Dart never needs storage permissions for it.
class IncomingTrackFile {
  const IncomingTrackFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Bridges Android's VIEW/SEND intents into Dart. No-op on non-Android
/// (web / other platforms have no equivalent "open with" path here).
///
/// Uses a MethodChannel only (no EventChannel): EventChannel's
/// receiveBroadcastStream reports a missing platform handler as a
/// FlutterError that fails widget tests, the same trap the satellite
/// badge avoided by staying on plain method calls.
class IncomingTrackOpener {
  IncomingTrackOpener._();

  static const _method = MethodChannel('com.rideatlas.app/open_file');

  static final StreamController<IncomingTrackFile> _controller =
      StreamController<IncomingTrackFile>.broadcast();

  static bool _started = false;

  /// Broadcast of every file the OS opens into RideAtlas (cold-start
  /// initial + later onNewIntent while the app is already running).
  static Stream<IncomingTrackFile> get stream => _controller.stream;

  /// Starts listening. Safe to call more than once; subsequent calls are
  /// no-ops. Call once the Flutter engine / method channels are ready.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _method.setMethodCallHandler((call) async {
      if (call.method == 'onOpened') {
        final file = _parse(call.arguments);
        if (file != null) _controller.add(file);
      }
    });

    try {
      final initial = await _method.invokeMethod<dynamic>('takeInitialOpen');
      final file = _parse(initial);
      if (file != null) _controller.add(file);
    } catch (_) {
      // Channel missing in tests / older APKs - ignore.
    }
  }

  static IncomingTrackFile? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final bytes = raw['bytes'];
    if (name is! String || name.isEmpty) return null;
    if (bytes is! Uint8List) {
      if (bytes is List<int>) {
        return IncomingTrackFile(name: name, bytes: Uint8List.fromList(bytes));
      }
      return null;
    }
    return IncomingTrackFile(name: name, bytes: bytes);
  }

  static void dispose() {
    _method.setMethodCallHandler(null);
    _started = false;
  }
}
