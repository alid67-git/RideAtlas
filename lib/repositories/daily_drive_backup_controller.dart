import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/track_point.dart';
import '../services/backup_folder_bridge.dart';
import '../services/daily_analysis.dart';
import '../services/daily_backup.dart';
import '../services/gps_recorder.dart';

const _metaBoxName = 'rideatlas_meta';
const _enabledKey = 'daily_drive_backup_enabled';
const _folderUriKey = 'daily_drive_backup_folder_uri';
const _folderNameKey = 'daily_drive_backup_folder_name';
const _backedUpDaysKey = 'daily_drive_backup_days';

/// Outcome of a catch-up / one-shot backup pass over the track points.
class DailyBackupRunResult {
  const DailyBackupRunResult({
    required this.written,
    required this.skipped,
    required this.failed,
  });

  /// Days newly written to the folder in this pass.
  final int written;

  /// Days already marked backed up (left alone).
  final int skipped;

  /// Days that had points but could not be written.
  final int failed;

  bool get hadWork => written > 0 || failed > 0;
}

/// Backs up **one local calendar day at a time** from a long multi-day
/// recording into a user-picked folder (typically Google Drive via Android
/// SAF). Never uploads the cumulative full session - only that day's
/// points, same bucketing as the analysis "Günlük" tab.
class DailyDriveBackupController extends ChangeNotifier {
  bool _loading = true;
  bool _enabled = false;
  String? _folderUri;
  String? _folderName;
  final Set<String> _backedUpDays = {};
  bool _busy = false;
  String? _lastError;
  String? _lastSuccessKey;
  /// Days currently being written - avoids duplicate parallel uploads.
  final Set<String> _inFlight = {};
  /// Serializes catch-up passes so GPS-tick storms don't pile up.
  Future<void> _queue = Future<void>.value();

  bool get isLoading => _loading;
  bool get enabled => _enabled;
  bool get isConfigured =>
      BackupFolderBridge.isSupported &&
      _enabled &&
      _folderUri != null &&
      _folderUri!.isNotEmpty;
  String? get folderName => _folderName;
  String? get folderUri => _folderUri;
  bool get isBusy => _busy;
  String? get lastError => _lastError;
  String? get lastSuccessKey => _lastSuccessKey;
  Set<String> get backedUpDays => Set.unmodifiable(_backedUpDays);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    _enabled = box.get(_enabledKey) == '1';
    _folderUri = box.get(_folderUriKey);
    _folderName = box.get(_folderNameKey);
    final rawDays = box.get(_backedUpDaysKey);
    _backedUpDays
      ..clear()
      ..addAll(_decodeDaySet(rawDays));
    _loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_enabledKey, value ? '1' : '0');
    notifyListeners();
  }

  Future<bool> pickFolder() async {
    final picked = await BackupFolderBridge.pickFolder();
    if (picked == null) return false;
    _folderUri = picked.uri;
    _folderName = picked.name;
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_folderUriKey, picked.uri);
    await box.put(_folderNameKey, picked.name);
    _lastError = null;
    notifyListeners();
    return true;
  }

  Future<void> clearFolder() async {
    _folderUri = null;
    _folderName = null;
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.delete(_folderUriKey);
    await box.delete(_folderNameKey);
    notifyListeners();
  }

  /// While a ride is in progress: upload every **completed** local day
  /// (strictly before today) that has not been backed up yet.
  Future<void> syncFromRecorder(GpsRecorder recorder) async {
    if (!isConfigured || recorder.isIdle) return;
    final points = List<TrackPoint>.from(recorder.points);
    await backupDaysPresent(points: points, includeToday: false);
  }

  /// After mid-ride save / finish / manual catch-up: write each present
  /// local day that is not yet marked backed up. Still one file per day.
  ///
  /// When [includeToday] is false, only days strictly before local today
  /// are considered (midnight catch-up). When true, today's segment is
  /// included (save / "write missing now").
  Future<DailyBackupRunResult> backupDaysPresent({
    required List<TrackPoint> points,
    bool includeToday = true,
  }) {
    final completer = Completer<DailyBackupRunResult>();
    _queue = _queue.then((_) async {
      final result = await _backupDaysPresentUnlocked(
        points: points,
        includeToday: includeToday,
      );
      completer.complete(result);
    }).catchError((Object e, StackTrace st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<DailyBackupRunResult> _backupDaysPresentUnlocked({
    required List<TrackPoint> points,
    required bool includeToday,
  }) async {
    if (!isConfigured) {
      return const DailyBackupRunResult(written: 0, skipped: 0, failed: 0);
    }
    final today = calendarDayLocal(DateTime.now());
    var written = 0;
    var skipped = 0;
    var failed = 0;
    for (final day in localDaysInPoints(points)) {
      if (!includeToday && !day.isBefore(today)) continue;
      final key = dayBackupKey(day);
      if (_backedUpDays.contains(key)) {
        skipped++;
        continue;
      }
      final ok = await ensureDayBackedUp(day: day, allPoints: points);
      if (ok) {
        written++;
      } else {
        failed++;
      }
    }
    return DailyBackupRunResult(
      written: written,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<bool> ensureDayBackedUp({
    required DateTime day,
    required List<TrackPoint> allPoints,
  }) async {
    if (!isConfigured) return false;
    final key = dayBackupKey(day);
    if (_backedUpDays.contains(key) || _inFlight.contains(key)) return true;

    final gpx = buildDayBackupGpx(allPoints: allPoints, day: day);
    if (gpx == null) return false;

    _inFlight.add(key);
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final uri = _folderUri!;
      final ok = await BackupFolderBridge.writeFile(
        uri: uri,
        fileName: dayBackupFileName(day),
        bytes: Uint8List.fromList(utf8.encode(gpx)),
      );
      if (!ok) {
        _lastError = key;
        return false;
      }
      _backedUpDays.add(key);
      _lastSuccessKey = key;
      final box = await Hive.openBox<String>(_metaBoxName);
      await box.put(_backedUpDaysKey, _encodeDaySet(_backedUpDays));
      return true;
    } catch (_) {
      _lastError = key;
      return false;
    } finally {
      _inFlight.remove(key);
      _busy = _inFlight.isNotEmpty;
      notifyListeners();
    }
  }
}

Set<String> _decodeDaySet(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return {for (final e in list) e.toString()};
  } catch (_) {
    return {};
  }
}

String _encodeDaySet(Set<String> days) {
  final list = days.toList()..sort();
  return jsonEncode(list);
}
