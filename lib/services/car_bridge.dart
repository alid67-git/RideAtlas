import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  CarBridge({required this._recorder, required this._routeRepository}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _recorder.addListener(_pushState);
    _channel.setMethodCallHandler(_handleCarCommand);
    _pushState();
  }

  final GpsRecorder _recorder;
  final RouteRepository _routeRepository;

  void _pushState() {
    // Fire-and-forget: nothing on the Dart side needs the result, and in
    // widget tests (which default to TargetPlatform.android) there's no
    // native handler registered at all, which throws MissingPluginException.
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
          })
          .catchError((_) {}),
    );
  }

  Future<void> _handleCarCommand(MethodCall call) async {
    switch (call.method) {
      case 'start':
        // Matches AppLocalizations.recordingNotificationTitle/Text's
        // Turkish text - the car screen has no BuildContext to look those
        // up through, and Turkish is the app's default/primary language.
        await _recorder.start(
          androidNotificationTitle: 'RideAtlas kayıt yapıyor',
          androidNotificationText: 'Rotanız arka planda kaydediliyor',
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

    final now = DateTime.now();
    final name =
        'Kayıt ${now.day} ${_monthNameTr(now.month)} ${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
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

  static const _trMonths = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  String _monthNameTr(int month) => _trMonths[month - 1];

  void dispose() {
    _recorder.removeListener(_pushState);
  }
}
