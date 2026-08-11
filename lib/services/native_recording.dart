import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';

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

  /// Points left over from a recording that was interrupted mid-ride - the
  /// whole app process got killed (e.g. an OEM's aggressive background-app
  /// management) before it ever reached an explicit stop/discard call, so
  /// the usual cleanup never ran. Empty if nothing is orphaned, or if a
  /// recording is currently active (nothing to recover from).
  static Future<List<Map<Object?, Object?>>> getOrphanedPoints() async {
    final raw = await _methods.invokeMethod<List<dynamic>>(
      'getOrphanedPoints',
    );
    return _castPointList(raw);
  }

  /// Deletes the leftover file once its points have been recovered (or the
  /// user chose not to keep them).
  static Future<void> clearOrphanedPoints() async {
    await _methods.invokeMethod<void>('clearOrphanedPoints');
  }

  static List<Map<Object?, Object?>> _castPointList(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw.map((e) => Map<Object?, Object?>.from(e as Map)).toList();
  }

  /// Converts raw native point maps (latitude/longitude/altitude/timeMs/...)
  /// into [TrackPoint]s, the same shape [GpsRecorder] builds internally.
  static List<TrackPoint> parsePoints(List<Map<Object?, Object?>> raw) {
    final points = <TrackPoint>[];
    for (final r in raw) {
      final lat = (r['latitude'] as num?)?.toDouble();
      final lng = (r['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final timeMs = (r['timeMs'] as num?)?.toInt();
      points.add(
        TrackPoint(
          latLng: LatLng(lat, lng),
          elevation: (r['altitude'] as num?)?.toDouble(),
          time: timeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
              : null,
        ),
      );
    }
    return points;
  }
}
