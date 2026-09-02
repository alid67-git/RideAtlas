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

  /// Files that arrived before anyone subscribed (cold-start
  /// [takeInitialOpen] used to fire into a broadcast stream with no
  /// listener and get dropped — the app opened but the ride was never
  /// imported).
  static final List<IncomingTrackFile> _pending = [];

  static bool _started = false;

  /// Broadcast of every file the OS opens into RideAtlas (cold-start
  /// initial + later onOpened while the app is already running).
  static Stream<IncomingTrackFile> get stream => _controller.stream;

  /// Subscribe, then drain anything queued before this listener existed.
  static StreamSubscription<IncomingTrackFile> listen(
    void Function(IncomingTrackFile file) onData,
  ) {
    final sub = _controller.stream.listen(onData);
    final queued = List<IncomingTrackFile>.from(_pending);
    _pending.clear();
    for (final file in queued) {
      onData(file);
    }
    return sub;
  }

  /// Starts listening. Safe to call more than once; subsequent calls are
  /// no-ops. Call once the Flutter engine / method channels are ready.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _method.setMethodCallHandler((call) async {
      if (call.method == 'onOpened') {
        final file = _parse(call.arguments);
        if (file != null) _emit(file);
      }
    });

    try {
      final initial = await _method.invokeMethod<dynamic>('takeInitialOpen');
      final file = _parse(initial);
      if (file != null) _emit(file);
    } catch (_) {
      // Channel missing in tests / older APKs - ignore.
    }
  }

  static void _emit(IncomingTrackFile file) {
    if (_controller.hasListener) {
      _controller.add(file);
    } else {
      _pending.add(file);
    }
  }

  /// Visible for tests.
  static IncomingTrackFile? parseForTest(dynamic raw) => _parse(raw);

  static IncomingTrackFile? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name'] ?? raw['name'.toString()];
    final nameStr = name is String ? name : null;
    if (nameStr == null || nameStr.isEmpty) return null;
    final bytes = raw['bytes'];
    final data = _asUint8List(bytes);
    if (data == null || data.isEmpty) return null;
    return IncomingTrackFile(name: nameStr, bytes: data);
  }

  static Uint8List? _asUint8List(dynamic bytes) {
    if (bytes is Uint8List) return bytes;
    if (bytes is ByteData) {
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    }
    if (bytes is List<int>) return Uint8List.fromList(bytes);
    return null;
  }

  static void dispose() {
    _method.setMethodCallHandler(null);
    _started = false;
    _pending.clear();
  }
}
