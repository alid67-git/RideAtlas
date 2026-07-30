import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';

const _distance = Distance();

enum RecordingState { idle, recording, paused }

/// Why [GpsRecorder.start] failed, so the UI can show a specific message.
enum RecordingStartError { serviceDisabled, permissionDenied }

/// Records the device's live position into a growing list of [TrackPoint]s
/// while the app is in the foreground. This only works while the browser tab
/// is active and the screen is on - there is no background/low-power mode,
/// since that would require a native (App Store) build rather than a web app.
class GpsRecorder extends ChangeNotifier {
  RecordingState _state = RecordingState.idle;
  final List<TrackPoint> _points = [];
  StreamSubscription<Position>? _sub;
  DateTime? _startedAt;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartedAt;

  RecordingState get state => _state;
  List<TrackPoint> get points => List.unmodifiable(_points);
  bool get isRecording => _state == RecordingState.recording;
  bool get isPaused => _state == RecordingState.paused;
  bool get isIdle => _state == RecordingState.idle;

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
  Future<RecordingStartError?> start() async {
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
    _state = RecordingState.recording;
    notifyListeners();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition);
    return null;
  }

  void _onPosition(Position pos) {
    if (_state != RecordingState.recording) return;
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
    _pauseStartedAt = DateTime.now();
    notifyListeners();
  }

  void resume() {
    if (_state != RecordingState.paused) return;
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null) {
      _pausedDuration += DateTime.now().difference(pauseStarted);
      _pauseStartedAt = null;
    }
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
    _state = RecordingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
