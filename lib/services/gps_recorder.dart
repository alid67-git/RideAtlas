import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/track_point.dart';
import 'battery_info.dart';
import 'gpx_parser.dart';
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
  // Stationary / traffic-light floor. Kept low so a slow walk (~3–5 km/h)
  // stays in the recording state instead of flipping into auto-pause.
  static const _autoPauseSpeedThresholdKmh = 1.5;
  // Resume as soon as motion is clearly above a crawl. Was 6 km/h, which
  // left walkers stuck on "Otomatik duraklatıldı" the whole way.
  static const _autoPauseResumeThresholdKmh = 2.5;
  // Phone GPS often reports speed ≈ 0 while walking; treat a real move away
  // from the pause spot as resume even when Doppler speed stays low.
  static const _autoPauseResumeDisplacementMeters = 20.0;
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
  // Kept incrementally instead of summed from _points on every read - a
  // multi-hour ride's point list keeps growing, and the record screen reads
  // distanceKm on every single GPS update (it watches this whole recorder
  // via context.watch), so a fresh full-list sum each time turns into
  // steadily worsening O(n) work per frame - the likely cause behind
  // reports of the app "closing on its own" partway through very long
  // recordings (thousands of Haversine calls a second by the end of an
  // 10+ hour ride, on the same isolate as the UI).
  double _distanceMeters = 0;
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
  /// Fix where auto-pause engaged - used for displacement-based resume.
  LatLng? _autoPauseOrigin;
  /// Previous fix while auto-paused - lets the resume check reject a single
  /// glitchy fix (a multipath reflection or a moment in a pocket reporting a
  /// 1-2 km jump) that would otherwise look like real movement and end a
  /// genuine stop early.
  LatLng? _lastAutoPauseFixLatLng;
  DateTime? _lastAutoPauseFixTime;
  int? _batteryStartPercent;
  final List<double> _recentSpeedsKmh = [];
  String _notificationTitle = 'RideAtlas';
  String _notificationText = 'Recording your ride';

  RecordingState get state => _state;
  int? get batteryStartPercent => _batteryStartPercent;

  /// Wall-clock time [start] was called, or null if idle. Unlike the track
  /// points themselves (GPS timestamps, which can be null/sparse), this is
  /// always the actual device clock reading - used to match this recording
  /// against the device's photo gallery by capture time. Stays set until
  /// [stop] or [discard] resets it, so callers must read it before calling
  /// either.
  DateTime? get startedAt => _startedAt;
  // A live view, not a copy - List.unmodifiable(_points) would allocate and
  // fill a whole new list on every single call, which is the same
  // steadily-worsening-with-ride-length cost distanceKm used to have (see
  // its comment above), for a getter that's read just as often.
  List<TrackPoint> get points => UnmodifiableListView(_points);
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

  double get distanceKm => _distanceMeters / 1000;

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
    _distanceMeters = 0;
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
    _autoPauseOrigin = null;
    _lastAutoPauseFixLatLng = null;
    _lastAutoPauseFixTime = null;
    _recentSpeedsKmh.clear();
    _lastAcceptedSpeedKmh = null;
    _lastAcceptedSpeedTime = null;
    _batteryStartPercent = await currentBatteryPercent();
    _notificationTitle = androidNotificationTitle;
    _notificationText = androidNotificationText;
    _state = RecordingState.recording;
    notifyListeners();

    if (NativeRecording.isSupported) {
      await NativeRecording.start(
        title: androidNotificationTitle,
        text: androidNotificationText,
        startedAtMs: _startedAt!.millisecondsSinceEpoch,
        manualPaused: false,
        batteryStartPercent: _batteryStartPercent,
      );
      _attachNativeListeners();
      unawaited(_persistSession());
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

  /// Snapshot of timers / pause history / flags for Android process death.
  /// Track points are already on disk (JSONL); this keeps km (via points),
  /// wall-clock start, and recording-vs-paused mode consistent on reopen.
  Future<void> _persistSession() async {
    if (!NativeRecording.isSupported || isIdle) return;
    final started = _startedAt;
    if (started == null) return;
    try {
      await NativeRecording.saveSession(
        startedAtMs: started.millisecondsSinceEpoch,
        manualPaused: _state == RecordingState.paused,
        nativePaused: _state == RecordingState.paused || _isAutoPaused,
        title: _notificationTitle,
        text: _notificationText,
        batteryStartPercent: _batteryStartPercent,
        pauseStartedAtMs: _pauseStartedAt?.millisecondsSinceEpoch,
        completedPauses: [
          for (final p in _completedPauses)
            {
              'durationMs': p.duration.inMilliseconds,
              'endMs': p.end.millisecondsSinceEpoch,
            },
        ],
      );
    } catch (_) {}
  }

  void _attachNativeListeners() {
    _nativeSub?.cancel();
    _nativePollTimer?.cancel();
    _nativeSub = NativeRecording.pointStream().listen(_applyNativePoint);
    // EventChannel drops while the UI isolate is frozen; the native
    // buffer still has every fix — poll as a safety net. Matches the
    // native 2s GPS cadence so we don't wake the isolate more often.
    _nativePollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_drainNativePoints());
    });
  }

  /// Re-attaches to an Android recording that survived process death (OEM
  /// kill, swipe-away, lock-screen) — Motion GPX-style: if we were
  /// recording/paused, open continues that session; if idle, stays idle.
  /// Returns true when a session was restored.
  Future<bool> tryRestoreInterruptedSession({
    String androidNotificationTitle = 'RideAtlas',
    String androidNotificationText = 'Recording your ride',
  }) async {
    if (!NativeRecording.isSupported || !isIdle) return false;

    try {
      final has = await NativeRecording.hasInterruptedSession();
      if (!has) return false;

      final session = await NativeRecording.getSession();
      final running = await NativeRecording.isRunning();
      final rawPoints = running
          ? await NativeRecording.getPoints()
          : await NativeRecording.getOrphanedPoints();

      // Session file missing but leftover points from an older build —
      // still treat as an interrupted ride rather than deleting silently.
      if (session == null && rawPoints.isEmpty && !running) {
        await NativeRecording.clearOrphanedPoints();
        return false;
      }

      final title = session?.title ?? androidNotificationTitle;
      final text = session?.text ?? androidNotificationText;
      final manualPaused = session?.manualPaused ?? false;
      final nativePaused = session?.nativePaused ?? manualPaused;
      final startedAtMs = session?.startedAtMs ??
          (rawPoints.isNotEmpty
              ? (rawPoints.first['timeMs'] as num?)?.toInt()
              : null) ??
          DateTime.now().millisecondsSinceEpoch;
      final battery = session?.batteryStartPercent;

      if (!running) {
        await NativeRecording.start(
          title: title,
          text: text,
          startedAtMs: startedAtMs,
          manualPaused: manualPaused,
          batteryStartPercent: battery,
        );
        if (nativePaused) {
          await NativeRecording.setPaused(
            true,
            manualPaused: manualPaused,
          );
        }
      }

      // Prefer the snapshot taken before startForegroundService - the
      // service loads the JSONL file asynchronously, so an immediate
      // getPoints() right after start can still be empty.
      var batch = rawPoints;
      if (batch.isEmpty) {
        batch = await NativeRecording.getPoints();
      }
      _rebuildPointsFromNative(batch);
      _nativeIngestedCount = batch.length;
      _startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
      _batteryStartPercent = battery;
      _notificationTitle = title;
      _notificationText = text;
      _completedPauses
        ..clear()
        ..addAll([
          for (final p in session?.completedPauses ?? const <NativeCompletedPause>[])
            (
              duration: Duration(milliseconds: p.durationMs),
              end: DateTime.fromMillisecondsSinceEpoch(p.endMs),
            ),
        ]);
      _isAutoPaused = false;
      _stationarySince = null;
      _autoPauseOrigin = null;
      _lastAutoPauseFixLatLng = null;
      _lastAutoPauseFixTime = null;
      if (manualPaused) {
        _state = RecordingState.paused;
        final pauseStartMs = session?.pauseStartedAtMs;
        _pauseStartedAt = pauseStartMs != null
            ? DateTime.fromMillisecondsSinceEpoch(pauseStartMs)
            : DateTime.now();
      } else {
        _state = RecordingState.recording;
        // Auto-pause may have left nativePaused true without manual pause —
        // keep GPS slow until motion resumes, but Dart stays "recording".
        if (nativePaused && !manualPaused) {
          _isAutoPaused = true;
          final pauseStartMs = session?.pauseStartedAtMs;
          _pauseStartedAt = pauseStartMs != null
              ? DateTime.fromMillisecondsSinceEpoch(pauseStartMs)
              : DateTime.now();
          if (_points.isNotEmpty) {
            _autoPauseOrigin = _points.last.latLng;
          }
        } else {
          _pauseStartedAt = null;
        }
      }
      _attachNativeListeners();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
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
  static const _maxPlausibleSpeedKmh = 250.0;

  /// How many recent points to re-scan for spike-and-return glitches after
  /// each fix ([findExcursionPointIndices] lookahead is ~150).
  static const _glitchPruneWindow = 220;

  /// Full-track glitch sweep every N accepted points so an old spike outside
  /// the recent window still gets cleaned once the return pattern is visible.
  static const _glitchFullScanInterval = 40;

  /// Cap on how many of the most recent points a "full" sweep re-scans.
  /// Without this, scanning the *entire* ride from the start on every sweep
  /// turns into ever-growing main-isolate work as a long recording keeps
  /// going (each sweep costs roughly current-length x lookahead) - the
  /// likely cause of reports of the map/UI locking up partway through
  /// multi-hour, multi-thousand-point rides. A spike further back than this
  /// has already been through the window scan on every point since, so
  /// capping the sweep keeps its cost constant instead of growing with the
  /// whole ride.
  static const _glitchFullScanMaxPoints = 3000;

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

  void _recomputeDistanceMeters() {
    _distanceMeters = 0;
    for (var i = 1; i < _points.length; i++) {
      _distanceMeters += _distance(_points[i - 1].latLng, _points[i].latLng);
    }
  }

  /// Drops GPS spike-and-return clusters live — same rules as saved-route
  /// cleanup ([filterImplausiblePoints]), so the red line does not shoot out
  /// to a wrong fix and snap back minutes later.
  void _pruneGpsGlitchPoints({required bool fullScan}) {
    if (_points.length < 4) return;
    final before = _points.length;
    final scanWindow = fullScan ? _glitchFullScanMaxPoints : _glitchPruneWindow;
    final start = _points.length > scanWindow ? _points.length - scanWindow : 0;
    final flagged = findImplausiblePointIndices(_points.sublist(start))
        .map((i) => i + start)
        .toSet();
    if (flagged.isEmpty) return;
    final kept = [
      for (var i = 0; i < _points.length; i++)
        if (!flagged.contains(i)) _points[i],
    ];
    _points
      ..clear()
      ..addAll(kept);
    if (_points.length == before) return;
    _recomputeDistanceMeters();
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
      final here = LatLng(pos.latitude, pos.longitude);
      _autoPauseOrigin ??= here;

      // A single fix that implies an impossible speed since the previous
      // one (same cap as the recording-side glitch filter) is a GPS glitch,
      // not the rider actually moving 1-2 km in a couple of seconds -
      // ignore it for resume purposes and keep waiting instead of ending
      // the stop.
      final prevFixLatLng = _lastAutoPauseFixLatLng;
      final prevFixTime = _lastAutoPauseFixTime;
      _lastAutoPauseFixLatLng = here;
      _lastAutoPauseFixTime = pos.timestamp;
      if (prevFixLatLng != null && prevFixTime != null) {
        final dtSeconds =
            pos.timestamp.difference(prevFixTime).inMilliseconds / 1000.0;
        if (dtSeconds > 0) {
          final impliedKmh =
              (_distance(prevFixLatLng, here) / dtSeconds) * 3.6;
          if (impliedKmh > _maxPlausibleSpeedKmh) {
            notifyListeners();
            return;
          }
        }
      }

      final movedMeters = _distance(_autoPauseOrigin!, here);
      final shouldResume =
          smoothedSpeedKmh >= _autoPauseResumeThresholdKmh ||
          movedMeters >= _autoPauseResumeDisplacementMeters;
      if (shouldResume) {
        _isAutoPaused = false;
        _stationarySince = null;
        _autoPauseOrigin = null;
        _lastAutoPauseFixLatLng = null;
        _lastAutoPauseFixTime = null;
        final pauseStarted = _pauseStartedAt;
        if (pauseStarted != null) {
          final now = DateTime.now();
          _completedPauses.add((duration: now.difference(pauseStarted), end: now));
          _pauseStartedAt = null;
        }
        // Back to the fast/high-accuracy GPS cadence now that the ride
        // has actually resumed - see the matching setPaused(true) below.
        if (NativeRecording.isSupported) {
          unawaited(NativeRecording.setPaused(false, manualPaused: false));
          unawaited(_persistSession());
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
        _autoPauseOrigin = LatLng(pos.latitude, pos.longitude);
        // Slows the native GPS request cadence while genuinely stationary
        // (see RecordingLocationService.buildLocationRequest) - auto-pause
        // was previously a display-only/recording filter that left GPS
        // polling at full rate the whole time, burning battery identically
        // whether the rider was moving or sitting at a light.
        if (NativeRecording.isSupported) {
          unawaited(NativeRecording.setPaused(true, manualPaused: false));
          unawaited(_persistSession());
        }
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
      final countAfterAdd = _points.length;
      _pruneGpsGlitchPoints(
        fullScan: countAfterAdd % _glitchFullScanInterval == 0,
      );
      if (_points.length == countAfterAdd && countAfterAdd > 1) {
        _distanceMeters += _distance(
          _points[countAfterAdd - 2].latLng,
          _points[countAfterAdd - 1].latLng,
        );
      }
    }
    notifyListeners();
  }

  void pause() {
    if (_state != RecordingState.recording) return;
    _state = RecordingState.paused;
    _pauseStartedAt ??= DateTime.now();
    if (NativeRecording.isSupported) {
      unawaited(NativeRecording.setPaused(true, manualPaused: true));
      unawaited(_persistSession());
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
    _autoPauseOrigin = null;
    _lastAutoPauseFixLatLng = null;
    _lastAutoPauseFixTime = null;
    _state = RecordingState.recording;
    if (NativeRecording.isSupported) {
      unawaited(NativeRecording.setPaused(false, manualPaused: false));
      unawaited(_persistSession());
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
    _distanceMeters = 0;
    _seenNativeTimeMs.clear();
    _isAutoPaused = false;
    _stationarySince = null;
    _autoPauseOrigin = null;
    _lastAutoPauseFixLatLng = null;
    _lastAutoPauseFixTime = null;
    _recentSpeedsKmh.clear();
    for (final raw in batch) {
      final lat = (raw['latitude'] as num?)?.toDouble();
      final lng = (raw['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final timeMs = (raw['timeMs'] as num?)?.toInt();
      if (timeMs != null && !_seenNativeTimeMs.add(timeMs)) continue;
      final altitude = (raw['altitude'] as num?)?.toDouble();
      final speedMs = (raw['speed'] as num?)?.toDouble() ?? 0;
      final latLng = LatLng(lat, lng);
      if (_points.isNotEmpty) {
        _distanceMeters += _distance(_points.last.latLng, latLng);
      }
      _points.add(
        TrackPoint(
          latLng: latLng,
          elevation: altitude,
          time: timeMs != null
              ? DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true)
              : null,
        ),
      );
      _currentSpeedKmh = speedMs > 0 ? speedMs * 3.6 : 0;
      _currentAltitude = altitude;
    }
    final cleaned = filterImplausiblePoints(_points);
    if (cleaned.length != _points.length) {
      _points
        ..clear()
        ..addAll(cleaned);
      _recomputeDistanceMeters();
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
    _distanceMeters = 0;
    _startedAt = null;
    _pauseStartedAt = null;
    _completedPauses.clear();
    _currentSpeedKmh = 0;
    _currentAltitude = null;
    _currentHeading = null;
    _isAutoPaused = false;
    _stationarySince = null;
    _autoPauseOrigin = null;
    _lastAutoPauseFixLatLng = null;
    _lastAutoPauseFixTime = null;
    _recentSpeedsKmh.clear();
    _lastAcceptedSpeedKmh = null;
    _lastAcceptedSpeedTime = null;
    _batteryStartPercent = null;
    _notificationTitle = 'RideAtlas';
    _notificationText = 'Recording your ride';
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
