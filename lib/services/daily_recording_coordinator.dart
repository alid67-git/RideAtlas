import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/track_point.dart';
import '../repositories/daily_mode_controller.dart';
import '../repositories/route_repository.dart';
import '../services/battery_optimization.dart';
import '../services/gps_recorder.dart';
import '../services/native_recording.dart';
import '../services/track_io.dart';

/// Result of [DailyRecordingCoordinator.onAppOpen].
enum DailyBootstrapResult {
  /// Nothing to do (idle, or platform unsupported).
  idle,

  /// Classic interrupted-session restore; Record screen was opened.
  classicRestored,

  /// Daily mode is recording (restored, rolled, or silently started).
  dailyRunning,

  /// Daily mode wanted to start but Always location isn't granted yet.
  needsPermission,
}

/// Orchestrates optional daily-mode auto recording: silent start/resume on
/// app open, one saved ride per local calendar day, midnight rollover.
class DailyRecordingCoordinator {
  DailyRecordingCoordinator({
    required GpsRecorder recorder,
    required RouteRepository routes,
    required DailyModeController dailyMode,
  }) : _recorder = recorder,
       _routes = routes,
       _dailyMode = dailyMode;

  final GpsRecorder _recorder;
  final RouteRepository _routes;
  final DailyModeController _dailyMode;

  Timer? _dayWatch;
  bool _busy = false;

  void dispose() {
    _dayWatch?.cancel();
    _dayWatch = null;
  }

  /// Keep / clear the midnight timer when daily mode or recording state
  /// changes while Home stays mounted (e.g. toggle in Settings).
  void syncDayWatch({
    required AppLocalizations l10n,
    required String localeLanguageCode,
  }) {
    if (_dailyMode.enabled && !_recorder.isIdle) {
      _ensureDayWatch(l10n: l10n, localeLanguageCode: localeLanguageCode);
    } else {
      _dayWatch?.cancel();
      _dayWatch = null;
    }
  }

  /// Call once from HomeMapScreen after the first frame when native
  /// recording is available. Classic mode still restores interrupted
  /// sessions into RecordScreen; daily mode stays silent on the map.
  Future<DailyBootstrapResult> onAppOpen({
    required AppLocalizations l10n,
    required String localeLanguageCode,
    required Future<void> Function() openRecordScreen,
  }) async {
    if (!DailyModeController.isSupported || !NativeRecording.isSupported) {
      return DailyBootstrapResult.idle;
    }

    // Always try restore first - works with or without daily mode.
    final restored = await _recorder.tryRestoreInterruptedSession(
      androidNotificationTitle: l10n.recordingNotificationTitle,
      androidNotificationText: l10n.recordingNotificationText,
    );

    if (!_dailyMode.enabled) {
      if (restored) {
        await openRecordScreen();
        return DailyBootstrapResult.classicRestored;
      }
      return DailyBootstrapResult.idle;
    }

    if (restored) {
      await _handleRestoredDailySession(
        l10n: l10n,
        localeLanguageCode: localeLanguageCode,
      );
      _ensureDayWatch(l10n: l10n, localeLanguageCode: localeLanguageCode);
      // Stay on home - recording indicator covers navigation; no confirm UI.
      return DailyBootstrapResult.dailyRunning;
    }

    if (_recorder.isIdle) {
      final started = await silentStart(l10n: l10n);
      if (started) {
        await _dailyMode.setSessionDay(DailyModeController.dayKey());
        _ensureDayWatch(l10n: l10n, localeLanguageCode: localeLanguageCode);
        return DailyBootstrapResult.dailyRunning;
      }
      return DailyBootstrapResult.needsPermission;
    }

    _ensureDayWatch(l10n: l10n, localeLanguageCode: localeLanguageCode);
    return DailyBootstrapResult.dailyRunning;
  }

  /// Interactive permission pass used when the user turns daily mode ON in
  /// Settings - the one place we may show system permission sheets.
  Future<void> preparePermissions() async {
    if (!DailyModeController.isSupported) return;
    if (!await isIgnoringBatteryOptimizations()) {
      await requestIgnoreBatteryOptimizations();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
  }

  /// Starts recording without in-app confirm dialogs. Returns false when
  /// location isn't already "Allow all the time" (caller can snackbar).
  Future<bool> silentStart({required AppLocalizations l10n}) async {
    if (!NativeRecording.isSupported) return false;
    if (!_recorder.isIdle) return true;

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) return false;

    // Best-effort battery exemption - system sheet only if not already set;
    // do not block start on it.
    if (!await isIgnoringBatteryOptimizations()) {
      unawaited(requestIgnoreBatteryOptimizations());
    }

    final error = await _recorder.start(
      androidNotificationTitle: l10n.recordingNotificationTitle,
      androidNotificationText: l10n.recordingNotificationText,
    );
    return error == null;
  }

  Future<void> _handleRestoredDailySession({
    required AppLocalizations l10n,
    required String localeLanguageCode,
  }) async {
    final started = _recorder.startedAt;
    if (started == null) return;
    final sessionDay = DailyModeController.dayKey(started);
    final today = DailyModeController.dayKey();
    await _dailyMode.setSessionDay(sessionDay);

    if (sessionDay == today) return;

    // Cross-day restore after battery death: save yesterday's ride, start today.
    await _rollToNewDay(
      l10n: l10n,
      localeLanguageCode: localeLanguageCode,
      closedDayKey: sessionDay,
    );
  }

  void _ensureDayWatch({
    required AppLocalizations l10n,
    required String localeLanguageCode,
  }) {
    _dayWatch?.cancel();
    if (!_dailyMode.enabled) return;
    _dayWatch = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        _checkDayRollover(
          l10n: l10n,
          localeLanguageCode: localeLanguageCode,
        ),
      );
    });
  }

  Future<void> _checkDayRollover({
    required AppLocalizations l10n,
    required String localeLanguageCode,
  }) async {
    if (!_dailyMode.enabled || _busy) return;
    if (_recorder.isIdle) return;
    final today = DailyModeController.dayKey();
    final sessionDay = _dailyMode.sessionDay ??
        (_recorder.startedAt != null
            ? DailyModeController.dayKey(_recorder.startedAt)
            : null);
    if (sessionDay == null || sessionDay == today) return;
    await _rollToNewDay(
      l10n: l10n,
      localeLanguageCode: localeLanguageCode,
      closedDayKey: sessionDay,
    );
  }

  Future<void> _rollToNewDay({
    required AppLocalizations l10n,
    required String localeLanguageCode,
    required String closedDayKey,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!_recorder.isIdle) {
        await _saveSessionAsDailyRide(
          l10n: l10n,
          localeLanguageCode: localeLanguageCode,
          dayKey: closedDayKey,
        );
      }
      final started = await silentStart(l10n: l10n);
      if (started) {
        await _dailyMode.setSessionDay(DailyModeController.dayKey());
      } else {
        await _dailyMode.setSessionDay(null);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveSessionAsDailyRide({
    required AppLocalizations l10n,
    required String localeLanguageCode,
    required String dayKey,
  }) async {
    if (_recorder.isIdle) return;
    final points = List<TrackPoint>.from(_recorder.points);
    final batteryStart = _recorder.batteryStartPercent;
    // Prefer stop() so native buffers flush; falls back to discard if empty.
    List<TrackPoint> savedPoints;
    try {
      savedPoints = await _recorder.stop();
    } catch (_) {
      savedPoints = points;
      await _recorder.discard();
    }
    if (savedPoints.length < 2) return;

    // Parse as a local calendar date (not UTC midnight) so the label
    // matches the day key in every timezone.
    final parts = dayKey.split('-');
    final dayDate = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final label = DateFormat(
      'd MMM yyyy',
      localeLanguageCode,
    ).format(dayDate);
    final name = l10n.dailyRecordingName(label);
    final gpx = exportTrack(
      name: name,
      points: savedPoints,
      waypoints: const [],
      format: TrackFormat.gpx,
    );
    try {
      await _routes.importFromBytes(
        bytes: Uint8List.fromList(utf8.encode(gpx)),
        suggestedFileName: '$name.gpx',
        batteryStartPercent: batteryStart,
        skipDuplicateCheck: true,
      );
    } catch (_) {
      // Don't block the new day's start if save fails.
    }
  }
}
