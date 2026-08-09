import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only bridge to [RecordingLocationService]. No-op stubs are not
/// provided - callers must gate on [isSupported].
class NativeRecording {
  static const _methods = MethodChannel('com.rideatlas.app/recording');
  static const _events = EventChannel('com.rideatlas.app/recording_events');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start({
    required String title,
    required String text,
  }) async {
    await _methods.invokeMethod<void>('start', {
      'title': title,
      'text': text,
    });
  }

  /// Stops the service and returns every buffered point (each a map with
  /// latitude/longitude/altitude/speed/timeMs/accuracy).
  static Future<List<Map<Object?, Object?>>> stop() async {
    final raw = await _methods.invokeMethod<List<dynamic>>('stop');
    return _castPointList(raw);
  }

  static Future<void> discard() async {
    await _methods.invokeMethod<void>('discard');
  }

  static Future<void> setPaused(bool paused) async {
    await _methods.invokeMethod<void>('setPaused', {'paused': paused});
  }

  static Future<List<Map<Object?, Object?>>> getPoints() async {
    final raw = await _methods.invokeMethod<List<dynamic>>('getPoints');
    return _castPointList(raw);
  }

  static Future<List<Map<Object?, Object?>>> getPointsSince(int index) async {
    final raw = await _methods.invokeMethod<List<dynamic>>(
      'getPointsSince',
      {'index': index},
    );
    return _castPointList(raw);
  }

  static Stream<Map<Object?, Object?>> pointStream() {
    return _events.receiveBroadcastStream().map((event) {
      return Map<Object?, Object?>.from(event as Map);
    });
  }

  static List<Map<Object?, Object?>> _castPointList(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw.map((e) => Map<Object?, Object?>.from(e as Map)).toList();
  }
}
