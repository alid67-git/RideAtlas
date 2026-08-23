import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';

/// Metadata for an in-progress (or interrupted) Android recording session.
class NativeRecordingSession {
  const NativeRecordingSession({
    required this.startedAtMs,
    required this.manualPaused,
    required this.nativePaused,
    required this.title,
    required this.text,
    this.batteryStartPercent,
  });

  final int startedAtMs;
  final bool manualPaused;
  final bool nativePaused;
  final String title;
  final String text;
  final int? batteryStartPercent;

  factory NativeRecordingSession.fromMap(Map<Object?, Object?> raw) {
    return NativeRecordingSession(
      startedAtMs: (raw['startedAtMs'] as num?)?.toInt() ?? 0,
      manualPaused: raw['manualPaused'] as bool? ?? false,
      nativePaused: raw['nativePaused'] as bool? ?? false,
      title: raw['title'] as String? ?? 'RideAtlas',
      text: raw['text'] as String? ?? 'Recording your ride',
      batteryStartPercent: (raw['batteryStartPercent'] as num?)?.toInt(),
    );
  }
}

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
    int? startedAtMs,
    bool manualPaused = false,
    int? batteryStartPercent,
  }) async {
    await _methods.invokeMethod<void>('start', {
      'title': title,
      'text': text,
      if (startedAtMs != null) 'startedAtMs': startedAtMs,
      'manualPaused': manualPaused,
      if (batteryStartPercent != null)
        'batteryStartPercent': batteryStartPercent,
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

  static Future<void> setPaused(
    bool paused, {
    bool? manualPaused,
  }) async {
    await _methods.invokeMethod<void>('setPaused', {
      'paused': paused,
      if (manualPaused != null) 'manualPaused': manualPaused,
    });
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

  static Future<bool> isRunning() async {
    return await _methods.invokeMethod<bool>('isRunning') ?? false;
  }

  static Future<NativeRecordingSession?> getSession() async {
    final raw = await _methods.invokeMethod<dynamic>('getSession');
    if (raw is! Map) return null;
    return NativeRecordingSession.fromMap(Map<Object?, Object?>.from(raw));
  }

  /// True when the FGS is alive, or a session/points file remains on disk
  /// from an interrupted ride (so Dart should try to resume).
  static Future<bool> hasInterruptedSession() async {
    return await _methods.invokeMethod<bool>('hasInterruptedSession') ?? false;
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
