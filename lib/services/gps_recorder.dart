import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import 'battery_info.dart';
import 'native_recording.dart';

const _distance = Distance();

enum RecordingState { idle, recording, paused }

/// Why [GpsRecorder.start] failed, so the UI can show a specific message.
enum RecordingStartError {
  serviceDisabled,
  permissionDenied,

  /// Android only: the OS still has the app on "while in use" location
  /// access. Screen-lock / background recording needs "Allow all the time".
  backgroundPermissionDenied,
}

/// Records the device's live position into a growing list of [TrackPoint]s.
///
/// On Android, GPS is collected by a native foreground service
/// ([NativeRecording]) so points keep arriving while the screen is off -
/// Dart-side geolocator streams freeze with the Flutter engine under Doze.
/// Elsewhere (web / desktop) this uses [Geolocator.getPositionStream] and
/// only works while the tab/window is active.
class GpsRecorder extends ChangeNotifier {
  static const _autoPauseSpeedThresholdKmh = 3.0;
  static const _autoPauseResumeThresholdKmh = 6.0;
  // Just a visual "waiting" cue while genuinely stationary (traffic light,
  // junction) - separate from what counts as a "mola" (see
  // _minMolaDuration below), so making this quick doesn't affect rest
  // detection at all.
  static const _autoPauseDelay = Duration(seconds: 3);
  static const _speedSmoothingWindow = 4;

  /// Only a stop lasting this long or more counts as an actual "mola" -
  /// shorter ones (a red light, a junction) are momentary, not rest, and
  /// riders don't want them padding out the rest-time figure or breaking up
  /// the ride into false stops. Matches the threshold
  /// [RouteGeographyAnalyzer.detectStops] uses for already-saved routes, so
  /// live and saved figures agree.
  static const _minMolaDuration = Duration(minutes: 10);

  RecordingState _state = RecordingState.idle;
  final List<TrackPoint> _points = [];
  StreamSubscription<Position>? _sub;
  StreamSubscription<Map<Object?, Object?>>? _nativeSub;
  Timer? _nativePollTimer;
  int _nativeIngestedCount = 0;
  final Set<int> _seenNativeTimeMs = {};
  DateTime? _startedAt;
  // Each completed pause (manual or auto), so only ones >= _minMolaDuration
  // count as "mola" - short ones fold back into elapsed/riding time instead
  // of their own bucket. Records the end time too, so "time since last
  // mola" can be reported.
  final List<({Duration duration, DateTime end})> _completedPauses = [];
  DateTime? _pauseStartedAt;
  double _currentSpeedKmh = 0;
  double? _currentAltitude;
  double? _currentHeading;
  bool _isAutoPaused = false;
  DateTime? _stationarySince;
  int? _batteryStartPercent;
  final List<double> _recentSpeedsKmh = [];

  RecordingState get state => _state;
  int? get batteryStartPercent => _batteryStartPercent;

  /// Wall-clock time [start] was called, or null if idle. Unlike the track
  /// points themselves (GPS timestamps, which can be null/sparse), this is
  /// always the actual device clock reading - used to match this recording
  /// against the device's photo gallery by capture time. Stays set until
  /// [stop] or [discard] resets it, so callers must read it before calling
  /// either.
  DateTime? get startedAt => _startedAt;
  List<TrackPoint> get points => List.unmodifiable(_points);
  bool get isRecording => _state == RecordingState.recording;
  bool get isPaused => _state == RecordingState.paused;
  bool get isIdle => _state == RecordingState.idle;
  double get currentSpeedKmh => _currentSpeedKmh;
  double? get currentAltitude => _currentAltitude;
  bool get isAutoPaused => _isAutoPaused;

  /// Live GPS heading in degrees (0-360, clockwise from north), or null
  /// until the device reports one while moving. Only updated above a small
  /// speed threshold, same as [record_screen.dart]'s own course-up map, so
  /// it doesn't jitter while stationary.
  double? get currentHeading => _currentHeading;

  /// Most recent recorded point's position, or null before the first fix.
  LatLng? get currentLatLng => _points.isEmpty ? null : _points.last.latLng;

  double get distanceKm {
    var total = 0.0;
    for (var i = 1; i < _points.length; i++) {
      total += _distance(_points[i - 1].latLng, _points[i].latLng);
    }
    return total / 1000;
  }

  /// Active/moving duration - wall-clock time since [start] minus every
  /// pause of [_minMolaDuration] or longer, AND minus whatever pause is
  /// currently in progress (however short). Riders want this to visibly
  /// freeze the instant they stop, not just once a stop turns into a real
  /// "mola" - but a stop under [_minMolaDuration] still doesn't count as
  /// rest once it ends, so its frozen time gets folded back in then (see
  /// the jump this produces: [elapsed] holds steady while paused, then
  /// catches up by the pause's length the moment it resumes, as long as
  /// that pause stayed under the mola threshold).
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final now = DateTime.now();
    var result = now.difference(started) - restDuration;
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null) {
      final currentPause = now.difference(pauseStarted);
      // Only subtract here if restDuration hasn't already counted it (it
      // starts counting in-progress pauses once they hit the threshold) -
      // otherwise this would double-subtract the same stretch.
      if (currentPause < _minMolaDuration) result -= currentPause;
    }
    return result;
  }

  /// Raw wall-clock time since [start], including every stop/pause - unlike
  /// [elapsed]. Null while idle.
  Duration? get totalDuration {
    final started = _startedAt;
    return started == null ? null : DateTime.now().difference(started);
  }

  /// Time spent on qualifying rests ([_minMolaDuration] or longer, manual or
  /// auto-pause) since [start]. Shorter stops don't count - see [elapsed].
  Duration get restDuration {
    var total = Duration.zero;
    for (final pause in _completedPauses) {
      if (pause.duration >= _minMolaDuration) total += pause.duration;
    }
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null) {
      final current = DateTime.now().difference(pauseStarted);
      if (current >= _minMolaDuration) total += current;
    }
    return total;
  }

  /// Wall-clock time since the end of the last qualifying rest (see
  /// [restDuration]), or since [start] if there hasn't been one yet. Null
  /// while idle. Zero while currently mid-mola (an in-progress pause that
  /// has already crossed [_minMolaDuration]) - "since the last rest ended"
  /// doesn't apply while still inside it; this starts counting up again
  /// only once that pause actually ends and riding resumes.
  Duration? get timeSinceLastRest {
    final started = _startedAt;
    if (started == null) return null;
    final now = DateTime.now();
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null && now.difference(pauseStarted) >= _minMolaDuration) {
      return Duration.zero;
    }
    DateTime? lastRestEnd;
    for (final pause in _completedPauses) {
      if (pause.duration >= _minMolaDuration) lastRestEnd = pause.end;
    }
    return now.difference(lastRestEnd ?? started);
  }

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
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return RecordingStartError.permissionDenied;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        permission != LocationPermission.always) {
      return RecordingStartError.backgroundPermissionDenied;
    }

    _points.clear();
    _nativeIngestedCount = 0;
    _seenNativeTimeMs.clear();
    _startedAt = DateTime.now();
    _completedPauses.clear();
    _pauseStartedAt = null;
    _currentSpeedKmh = 0;
    _currentAltitude = null;
    _currentHeading = null;
    _isAutoPaused = false;
    _stationarySince = null;
    _recentSpeedsKmh.clear();
    _lastAcceptedSpeedKmh = null;
    _lastAcceptedSpeedTime = null;
    _batteryStartPercent = await currentBatteryPercent();
    _state = RecordingState.recording;
    notifyListeners();

    if (NativeRecording.isSupported) {
      await NativeRecording.start(
        title: androidNotificationTitle,
        text: androidNotificationText,
      );
      _nativeSub = NativeRecording.pointStream().listen(_applyNativePoint);
      // EventChannel drops while the UI isolate is frozen; the native
      // buffer still has every fix — poll as a safety net.
      _nativePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_drainNativePoints());
      });
    } else {
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_onPosition);
    }
    return null;
  }

  Future<void> _drainNativePoints() async {
    if (!NativeRecording.isSupported || _state == RecordingState.idle) return;
    try {
      final batch = await NativeRecording.getPointsSince(_nativeIngestedCount);
      for (final raw in batch) {
        _applyNativePoint(raw);
        _nativeIngestedCount++;
      }
    } catch (_) {}
  }

  void _applyNativePoint(Map<Object?, Object?> raw) {
    final lat = (raw['latitude'] as num?)?.toDouble();
    final lng = (raw['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final timeMs = (raw['timeMs'] as num?)?.toInt();
    if (timeMs != null && !_seenNativeTimeMs.add(timeMs)) return;

    final altitude = (raw['altitude'] as num?)?.toDouble() ?? 0;
    final speedMs = (raw['speed'] as num?)?.toDouble() ?? 0;
    final bearing = (raw['bearing'] as num?)?.toDouble() ?? 0;
    _onPosition(
      Position(
        longitude: lng,
        latitude: lat,
        timestamp: timeMs != null
            ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
            : DateTime.now(),
        accuracy: (raw['accuracy'] as num?)?.toDouble() ?? 0,
        altitude: altitude,
        altitudeAccuracy: 0,
        heading: bearing,
        headingAccuracy: 0,
        speed: speedMs,
        speedAccuracy: 0,
      ),
    );
  }

  double _smoothedSpeedKmh(double reading) {
    _recentSpeedsKmh.add(reading);
    if (_recentSpeedsKmh.length > _speedSmoothingWindow) {
      _recentSpeedsKmh.removeAt(0);
    }
    return _recentSpeedsKmh.reduce((a, b) => a + b) / _recentSpeedsKmh.length;
  }

  /// Rejects a speed reading that implies physically implausible
  /// acceleration/deceleration since the last accepted one (a GPS glitch -
  /// a single bad fix or a momentary Doppler misread - not real riding),
  /// keeping the last good value instead of a spike. Generous enough
  /// (~8 m/s^2) to allow genuine hard acceleration/braking through.
  static const _maxAccelerationKmhPerSec = 30.0;
  double? _lastAcceptedSpeedKmh;
  DateTime? _lastAcceptedSpeedTime;

  double _plausibleSpeedKmh(double rawKmh, DateTime time) {
    final lastKmh = _lastAcceptedSpeedKmh;
    final lastTime = _lastAcceptedSpeedTime;
    if (lastKmh != null && lastTime != null) {
      final dtSeconds = time.difference(lastTime).inMilliseconds / 1000.0;
      if (dtSeconds > 0 &&
          (rawKmh - lastKmh).abs() > _maxAccelerationKmhPerSec * dtSeconds) {
        return lastKmh;
      }
    }
    _lastAcceptedSpeedKmh = rawKmh;
    _lastAcceptedSpeedTime = time;
    return rawKmh;
  }

  /// Above any real vehicle speed this app expects to record - a fix that
  /// implies faster than this since the last *accepted* point is a
  /// reflected/multipath GPS glitch (common near junctions, tall buildings,
  /// underpasses), not real motion. Rejected points are simply left out of
  /// the track rather than accepted-then-corrected, so a bad fix can't
  /// spike the drawn route out to some other spot and back. Comparing
  /// against the last *accepted* point (not the last raw fix) means a run
  /// of several consecutive bad fixes gets skipped in full rather than each
  /// one anchoring the next comparison to more noise.
  static const _maxPlausibleSpeedKmh = 300.0;

  bool _isPlausiblePoint(LatLng latLng, DateTime time) {
    if (_points.isEmpty) return true;
    final last = _points.last;
    final lastTime = last.time;
    if (lastTime == null) return true;
    final dtSeconds = time.difference(lastTime).inMilliseconds / 1000.0;
    if (dtSeconds <= 0) return true;
    final meters = _distance(last.latLng, latLng);
    final impliedKmh = (meters / dtSeconds) * 3.6;
    return impliedKmh <= _maxPlausibleSpeedKmh;
  }

  void _onPosition(Position pos) {
    if (_state != RecordingState.recording) return;

    final rawSpeedKmh = (pos.speed.isFinite && pos.speed > 0)
        ? pos.speed * 3.6
        : 0.0;
    final speedKmh = _plausibleSpeedKmh(rawSpeedKmh, pos.timestamp);
    _currentSpeedKmh = speedKmh;
    _currentAltitude = pos.altitude;
    final smoothedSpeedKmh = _smoothedSpeedKmh(speedKmh);
    if (pos.heading.isFinite && pos.heading >= 0 && smoothedSpeedKmh > 3) {
      _currentHeading = pos.heading;
    }

    if (_isAutoPaused) {
      if (smoothedSpeedKmh >= _autoPauseResumeThresholdKmh) {
        _isAutoPaused = false;
        _stationarySince = null;
        final pauseStarted = _pauseStartedAt;
        if (pauseStarted != null) {
          final now = DateTime.now();
          _completedPauses.add((duration: now.difference(pauseStarted), end: now));
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

    final latLng = LatLng(pos.latitude, pos.longitude);
    if (_isPlausiblePoint(latLng, pos.timestamp)) {
      _points.add(
        TrackPoint(
          latLng: latLng,
          elevation: pos.altitude,
          time: pos.timestamp,
        ),
      );
    }
    notifyListeners();
  }

  void pause() {
    if (_state != RecordingState.recording) return;
    _state = RecordingState.paused;
    _pauseStartedAt ??= DateTime.now();
    if (NativeRecording.isSupported) {
      unawaited(NativeRecording.setPaused(true));
    }
    notifyListeners();
  }

  void resume() {
    if (_state != RecordingState.paused) return;
    final pauseStarted = _pauseStartedAt;
    if (pauseStarted != null) {
      final now = DateTime.now();
      _completedPauses.add((duration: now.difference(pauseStarted), end: now));
      _pauseStartedAt = null;
    }
    _isAutoPaused = false;
    _stationarySince = null;
    _state = RecordingState.recording;
    if (NativeRecording.isSupported) {
      unawaited(NativeRecording.setPaused(false));
    }
    notifyListeners();
  }

  /// Ends the session and returns the recorded points, resetting to idle.
  Future<List<TrackPoint>> stop() async {
    if (NativeRecording.isSupported) {
      try {
        final batch = await NativeRecording.stop();
        // Authoritative rebuild: includes every fix collected while Flutter
        // was frozen with the screen off.
        _rebuildPointsFromNative(batch);
      } catch (_) {
        await _drainNativePoints();
        try {
          await NativeRecording.discard();
        } catch (_) {}
      }
    }
    final result = List<TrackPoint>.from(_points);
    _reset();
    return result;
  }

  void _rebuildPointsFromNative(List<Map<Object?, Object?>> batch) {
    // Take every native fix as-is. Re-running live auto-pause against a
    // burst of historical points would use wall-clock delays incorrectly
    // and drop real movement that happened while the screen was off.
    _points.clear();
    _seenNativeTimeMs.clear();
    _isAutoPaused = false;
    _stationarySince = null;
    _recentSpeedsKmh.clear();
    for (final raw in batch) {
      final lat = (raw['latitude'] as num?)?.toDouble();
      final lng = (raw['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final timeMs = (raw['timeMs'] as num?)?.toInt();
      if (timeMs != null && !_seenNativeTimeMs.add(timeMs)) continue;
      final altitude = (raw['altitude'] as num?)?.toDouble();
      final speedMs = (raw['speed'] as num?)?.toDouble() ?? 0;
      _points.add(
        TrackPoint(
          latLng: LatLng(lat, lng),
          elevation: altitude,
          time: timeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
              : null,
        ),
      );
      _currentSpeedKmh = speedMs > 0 ? speedMs * 3.6 : 0;
      _currentAltitude = altitude;
    }
  }

  Future<void> discard() async {
    if (NativeRecording.isSupported) {
      try {
        await NativeRecording.discard();
      } catch (_) {}
    }
    _reset();
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _nativeSub?.cancel();
    _nativeSub = null;
    _nativePollTimer?.cancel();
    _nativePollTimer = null;
    _nativeIngestedCount = 0;
    _seenNativeTimeMs.clear();
    _points.clear();
    _startedAt = null;
    _pauseStartedAt = null;
    _completedPauses.clear();
    _currentSpeedKmh = 0;
    _currentAltitude = null;
    _currentHeading = null;
    _isAutoPaused = false;
    _stationarySince = null;
    _recentSpeedsKmh.clear();
    _lastAcceptedSpeedKmh = null;
    _lastAcceptedSpeedTime = null;
    _batteryStartPercent = null;
    _state = RecordingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nativeSub?.cancel();
    _nativePollTimer?.cancel();
    super.dispose();
  }
}
