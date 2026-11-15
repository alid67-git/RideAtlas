import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/resolved_language.dart';
import '../repositories/route_repository.dart';
import 'battery_info.dart';
import 'gps_recorder.dart';
import 'track_io.dart';

const _channel = MethodChannel('com.rideatlas.app/car');

/// Android-only: mirrors [GpsRecorder]'s live state to the native Android
/// Auto screen (android/app/src/main/kotlin/.../car/) and relays button
/// taps from there back into the recorder. A no-op everywhere else - there
/// is no CarPlay/Android Automotive equivalent wired up yet.
class CarBridge {
  CarBridge({
    required GpsRecorder recorder,
    required RouteRepository routeRepository,
  }) : _recorder = recorder,
       _routeRepository = routeRepository {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _recorder.addListener(_pushState);
    _channel.setMethodCallHandler(_handleCarCommand);
    _pushState();
  }

  final GpsRecorder _recorder;
  final RouteRepository _routeRepository;

  /// Re-send the latest snapshot (e.g. after the in-app language changes
  /// so Android Auto copy switches with it).
  void refresh() => _pushState();

  void _pushState() {
    // Fire-and-forget: nothing on the Dart side needs the result, and in
    // widget tests (which default to TargetPlatform.android) there's no
    // native handler registered at all, which throws MissingPluginException.
    final copy = _carCopy();
    unawaited(
      _channel
          .invokeMethod('updateState', {
            'state': _recorder.isRecording
                ? 'recording'
                : _recorder.isPaused
                ? 'paused'
                : 'idle',
            'speedKmh': _recorder.currentSpeedKmh,
            'distanceKm': _recorder.distanceKm,
            'durationSeconds': _recorder.elapsed.inSeconds,
            'altitudeMeters': _recorder.currentAltitude,
            'isAutoPaused': _recorder.isAutoPaused,
            'lat': _recorder.currentLatLng?.latitude,
            'lng': _recorder.currentLatLng?.longitude,
            'headingDegrees': _recorder.currentHeading,
            'idleHint': copy.idleHint,
            'startTitle': copy.startTitle,
            'speedUnit': copy.speedUnit,
          })
          .catchError((_) {}),
    );
  }

  Future<void> _handleCarCommand(MethodCall call) async {
    switch (call.method) {
      case 'start':
        final copy = _carCopy();
        await _recorder.start(
          androidNotificationTitle: copy.notificationTitle,
          androidNotificationText: copy.notificationText,
        );
      case 'pause':
        _recorder.pause();
      case 'resume':
        _recorder.resume();
      case 'finish':
        await _finishFromCar();
    }
  }

  /// No text entry from the car screen - driver-distraction rules rule
  /// that out while moving - so this saves immediately under the same
  /// auto-generated name RecordScreen offers before a rider edits it by
  /// hand on the phone.
  Future<void> _finishFromCar() async {
    final batteryStart = _recorder.batteryStartPercent;
    final batteryEnd = await currentBatteryPercent();
    final points = await _recorder.stop();
    if (points.isEmpty) return;

    final name = _recordingName(DateTime.now());
    final gpx = exportTrack(
      name: name,
      points: points,
      waypoints: const [],
      format: TrackFormat.gpx,
    );
    final bytes = Uint8List.fromList(utf8.encode(gpx));
    await _routeRepository.importFromBytes(
      bytes: bytes,
      suggestedFileName: '$name.gpx',
      batteryStartPercent: batteryStart,
      batteryEndPercent: batteryEnd,
      skipDuplicateCheck: true,
    );
  }

  String _recordingName(DateTime now) {
    final code = resolvedLanguageCode();
    final date = DateFormat(
      'd MMM yyyy HH:mm',
      code == 'de'
          ? 'de'
          : code == 'en'
          ? 'en'
          : 'tr',
    ).format(now);
    switch (code) {
      case 'en':
        return 'Recording $date';
      case 'de':
        return 'Aufzeichnung $date';
      default:
        return 'Kayıt $date';
    }
  }

  _CarCopy _carCopy() {
    switch (resolvedLanguageCode()) {
      case 'en':
        return const _CarCopy(
          idleHint: 'Tap to start recording',
          startTitle: 'Start recording',
          speedUnit: 'km/h',
          notificationTitle: 'RideAtlas is recording',
          notificationText: 'Your ride is being tracked in the background',
        );
      case 'de':
        return const _CarCopy(
          idleHint: 'Tippen, um die Aufzeichnung zu starten',
          startTitle: 'Aufzeichnung starten',
          speedUnit: 'km/h',
          notificationTitle: 'RideAtlas zeichnet auf',
          notificationText: 'Ihre Fahrt wird im Hintergrund aufgezeichnet',
        );
      default:
        return const _CarCopy(
          idleHint: 'Kayda başlamak için dokunun',
          startTitle: 'Kayda başla',
          speedUnit: 'km/s',
          notificationTitle: 'RideAtlas kayıt yapıyor',
          notificationText: 'Rotanız arka planda kaydediliyor',
        );
    }
  }

  void dispose() {
    _recorder.removeListener(_pushState);
  }
}

class _CarCopy {
  const _CarCopy({
    required this.idleHint,
    required this.startTitle,
    required this.speedUnit,
    required this.notificationTitle,
    required this.notificationText,
  });

  final String idleHint;
  final String startTitle;
  final String speedUnit;
  final String notificationTitle;
  final String notificationText;
}
