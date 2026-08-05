import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import 'battery_info.dart';

const _distance = Distance();

enum RecordingState { idle, recording, paused }

/// Why [GpsRecorder.start] failed, so the UI can show a specific message.
enum RecordingStartError { serviceDisabled, permissionDenied }

/// Records the device's live position into a growing list of [TrackPoint]s
/// while the app is in the foreground. This only works while the browser tab
/// is active and the screen is on - there is no background/low-power mode,
/// since that would require a native (App Store) build rather than a web app.
class GpsRecorder extends ChangeNotifier {
  /// Below this speed, the rider is considered stationary (traffic light,
  /// fuel stop, etc.) for auto-pause purposes. Compared against a smoothed
  /// speed (see [_smoothedSpeedKmh]), not the raw GPS reading - a stationary
  /// phone's instantaneous GPS speed routinely jitters anywhere from 0 up to
  /// 2-3 km/h on positional noise alone, so comparing the raw value against
  /// a low threshold made real stops inconsistent to detect (a single noisy
  /// spike above the threshold reset the stationary timer).
  static const _autoPauseSpeedThresholdKmh = 3.0;

  /// Above this speed (with hysteresis above the pause threshold, so GPS
  /// jitter around walking pace doesn't flicker the state), auto-pause lifts.
  static const _autoPauseResumeThresholdKmh = 6.0;

  /// How long the rider must stay under the threshold before auto-pause
  /// kicks in - long enough that a normal stop-sign or gear shift doesn't
  /// trigger it.
  static const _autoPauseDelay = Duration(seconds: 15);

  /// How many recent speed readings [_smoothedSpeedKmh] averages over.
  static const _speedSmoothingWindow = 4;

  RecordingState _state = RecordingState.idle;
  final List<TrackPoint> _points = [];
  StreamSubscription<Position>? _sub;
  DateTime? _startedAt;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartedAt;
  double _currentSpeedKmh = 0;
  double? _currentAltitude;
  bool _isAutoPaused = false;
  DateTime? _stationarySince;
  int? _batteryStartPercent;
  final List<double> _recentSpeedsKmh = [];

  RecordingState get state => _state;
  /// Battery level (0-100) when [start] was called, or null if it couldn't
  /// be read on this platform. Captured once and kept through pause/resume;
  /// the matching end-of-ride reading is taken by the caller when finishing.
  int? get batteryStartPercent => _batteryStartPercent;
  List<TrackPoint> get points => List.unmodifiable(_points);
  bool get isRecording => _state == RecordingState.recording;
  bool get isPaused => _state == RecordingState.paused;
  bool get isIdle => _state == RecordingState.idle;
  double get currentSpeedKmh => _currentSpeedKmh;
  double? get currentAltitude => _currentAltitude;

  /// True while [isRecording] but the rider has been stationary long enough
  /// that new points/time aren't being accumulated. Distinct from [isPaused]
  /// (a manual pause) so the UI can show a lighter "auto-paused" hint
  /// instead of the full paused state.
  bool get isAutoPaused => _isAutoPaused;

  double get distanceKm {
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      total += _distance(_points[i - 1].latLng, _points[i].latLng);
    }
    return total / 1000;
  }

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final pausedSoFar = _pauseStartedAt != null
        ? _pausedDuration + DateTime.now().difference(_pauseStartedAt!)
        : _pausedDuration;
    return DateTime.now().difference(started) - pausedSoFar;
  }

  /// Returns null on success, or the reason it couldn't start.
  ///
  /// [androidNotificationTitle]/[androidNotificationText] are only used on
  /// Android, where a foreground service with a persistent notification is
  /// required to keep tracking while the app is minimized.
  Future<RecordingStartError?> start({
    String androidNotificationTitle = 'RideAtlas',
    String androidNotificationText = 'Recording your ride',
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return RecordingStartError.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return RecordingStartError.permissionDenied;
    }

    _points.clear();
    _startedAt = DateTime.now();
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _currentSpeedKmh = 0;
    _currentAltitude = null;
    _isAutoPaused = false;
    _stationarySince = null;
    _recentSpeedsKmh.clear();
    _batteryStartPercent = await currentBatteryPercent();
    _state = RecordingState.recording;
    notifyListeners();

    _sub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(
        notificationTitle: androidNotificationTitle,
        notificationText: androidNotificationText,
      ),
    ).listen(_onPosition);
    return null;
  }

  /// On Android, wraps the location settings with a foreground-service
  /// notification so tracking survives the app being minimized. Other
  /// platforms (including web) get the plain settings, since only Android's
  /// federated geolocator plugin supports this.
  LocationSettings _buildLocationSettings({
    required String notificationTitle,
    required String notificationText,
  }) {
    const accuracy = LocationAccuracy.high;
    const distanceFilter = 5;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  /// Appends [reading] to the rolling window and returns its average, so
  /// auto-pause decisions react to sustained speed rather than a single
  /// noisy GPS sample.
  double _smoothedSpeedKmh(double reading) {
    _recentSpeedsKmh.add(reading);
    if (_recentSpeedsKmh.length > _speedSmoothingWindow) {
      _recentSpeedsKmh.removeAt(0);
    }
    return _recentSpeedsKmh.reduce((a, b) => a + b) / _recentSpeedsKmh.length;
  }

  void _onPosition(Position pos) {
    if (_state != RecordingState.recording) return;

    final speedKmh = (pos.speed.isFinite && pos.speed > 0)
        ? pos.speed * 3.6
        : 0.0;
    _currentSpeedKmh = speedKmh;
    _currentAltitude = pos.altitude;
    final smoothedSpeedKmh = _smoothedSpeedKmh(speedKmh);

    if (_isAutoPaused) {
      if (smoothedSpeedKmh >= _autoPauseResumeThresholdKmh) {
        _isAutoPaused = false;
        _stationarySince = null;
        final pauseStarted = _pauseStartedAt;
        if (pauseStarted != null) {
          _pausedDuration += DateTime.now().difference(pauseStarted);
          _pauseStartedAt = null;
        }
      } else {
        notifyListeners();
        return;
      }
    } else if (smoothedSpeedKmh < _autoPauseSpeedThresholdKmh) {
      _stationarySince ??= DateTime.now();
      if (DateTime.now().difference(_stationarySince!) >= _autoPauseDelay) {
        _isAutoPaused = true;
        _pauseStartedAt = DateTime.now();
        notifyListeners();
        return;
      }
    } else {
      _stationarySince = null;
    }

    _points.add(
      TrackPoint(
        latLng: LatLng(pos.latitude, pos.longitude),
        elevation: pos.altitude,
        time: pos.timestamp,
      ),
    );
    notifyListeners();
  }

  void pause() {
    if (_state != RecordingState.recording) return;
    _state = RecordingState.paused;
    // If already auto-paused, keep the original pause start so that
    // stationary time isn't undercounted.
    _pauseStartedAt ??= DateTime.now();
    notifyListeners();
  }

  void resume() {
    if (_state != RecordingState.paused) return;
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null) {
      _pausedDuration += DateTime.now().difference(pauseStarted);
      _pauseStartedAt = null;
    }
    _isAutoPaused = false;
    _stationarySince = null;
    _state = RecordingState.recording;
    notifyListeners();
  }

  /// Ends the session and returns the recorded points, resetting to idle.
  List<TrackPoint> stop() {
    final result = List<TrackPoint>.from(_points);
    _reset();
    return result;
  }

  /// Ends the session without keeping the recorded points.
  void discard() => _reset();

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _points.clear();
    _startedAt = null;
    _pauseStartedAt = null;
    _pausedDuration = Duration.zero;
    _currentSpeedKmh = 0;
    _currentAltitude = null;
    _isAutoPaused = false;
    _stationarySince = null;
    _recentSpeedsKmh.clear();
    _batteryStartPercent = null;
    _state = RecordingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
