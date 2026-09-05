import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/gpx_route.dart';
import '../services/gpx_parser.dart';
import '../services/track_io.dart';

const _boxName = 'rideatlas_routes';
const _indexKey = 'index';
const _uuid = Uuid();

String _contentKey(String id) => 'content_$id';

/// Thrown when [RouteRepository.importFromBytes] finds an already-saved
/// ride with the same track fingerprint. [existing] is the copy already
/// in the library - callers typically open it instead of importing again.
class DuplicateRouteException implements Exception {
  DuplicateRouteException(this.existing);

  final GpxRoute existing;

  @override
  String toString() => 'DuplicateRouteException(${existing.id})';
}

/// Owns the set of imported GPX routes: persists their raw GPX text and
/// cached summary stats in a [Hive] box so the list screen can render
/// instantly without re-parsing GPX on every launch. Hive is backed by
/// IndexedDB on web (a much larger quota than SharedPreferences/localStorage)
/// and by a local file on mobile/desktop, so imports work uniformly across
/// platforms regardless of GPX file size.
class RouteRepository extends ChangeNotifier {
  final List<GpxRoute> _routes = [];
  bool _loading = true;
  Box<String>? _box;

  /// Newest ride first ([GpxRoute.recordedAt] descending). The list is kept
  /// sorted in memory after every load/import/edit - the getter does **not**
  /// re-read GPX files or re-sort from scratch on every rebuild.
  List<GpxRoute> get routes => List.unmodifiable(_routes);

  bool get isLoading => _loading;

  Future<Box<String>> _openBox() async {
    return _box ??= await Hive.openBox<String>(_boxName);
  }

  /// Newest [recordedAt] first; [importedAt] breaks ties so two rides from
  /// the same second stay stable.
  void _sortInPlace() {
    _routes.sort((a, b) {
      final byRecorded = b.recordedAt.compareTo(a.recordedAt);
      if (byRecorded != 0) return byRecorded;
      return b.importedAt.compareTo(a.importedAt);
    });
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final box = await _openBox();
    final raw = box.get(_indexKey);
    final list = raw == null ? const [] : jsonDecode(raw) as List<dynamic>;
    final missingRecordedAt = <String>{};
    final missingFingerprint = <String>{};
    final missingPreview = <String>{};
    _routes
      ..clear()
      ..addAll(
        list.map((e) {
          final json = e as Map<String, dynamic>;
          if (json['recordedAt'] == null) {
            missingRecordedAt.add(json['id'] as String);
          }
          if (json['trackFingerprint'] == null) {
            missingFingerprint.add(json['id'] as String);
          }
          if (json['previewPoints'] == null) {
            missingPreview.add(json['id'] as String);
          }
          return GpxRoute.fromJson(json);
        }),
      );
    _sortInPlace();

    _loading = false;
    notifyListeners();

    // One-shot backfills: only touch routes whose index row is missing the
    // field. List display itself never re-parses GPX for sorting.
    if (missingRecordedAt.isNotEmpty ||
        missingFingerprint.isNotEmpty ||
        missingPreview.isNotEmpty) {
      await _backfillIndexFields(
        box,
        missingRecordedAt: missingRecordedAt,
        missingFingerprint: missingFingerprint,
        missingPreview: missingPreview,
      );
    }
  }

  Future<void> _backfillIndexFields(
    Box<String> box, {
    required Set<String> missingRecordedAt,
    required Set<String> missingFingerprint,
    required Set<String> missingPreview,
  }) async {
    final needParse = {
      ...missingRecordedAt,
      ...missingFingerprint,
      ...missingPreview,
    };
    var changed = false;
    for (var i = 0; i < _routes.length; i++) {
      final route = _routes[i];
      if (!needParse.contains(route.id)) continue;
      final xml = box.get(_contentKey(route.id));
      if (xml == null) continue;
      try {
        final parsed = await compute(parseTrackXml, xml);
        var next = route;
        if (missingRecordedAt.contains(route.id)) {
          final start = trackTimeRange(parsed.points).start;
          if (start != null && start != route.recordedAt) {
            next = next.copyWith(recordedAt: start);
          }
        }
        if (missingFingerprint.contains(route.id) &&
            (next.trackFingerprint == null || next.trackFingerprint!.isEmpty)) {
          next = next.copyWith(
            trackFingerprint: trackFingerprint(parsed.points),
          );
        }
        if (missingPreview.contains(route.id) && next.previewPoints == null) {
          final preview = routePreviewPoints(parsed.points);
          if (preview != null) {
            next = next.copyWith(previewPoints: preview);
          }
        }
        if (next != route) {
          _routes[i] = next;
          changed = true;
        }
      } catch (_) {
        // Keep existing index row; do not block list load on a bad file.
      }
    }
    if (!changed) return;
    _sortInPlace();
    await _persistIndex(box);
    notifyListeners();
  }

  GpxRoute? _findByFingerprint(String fingerprint) {
    for (final r in _routes) {
      if (r.trackFingerprint == fingerprint) return r;
    }
    return null;
  }

  /// Imports a GPX, KML or KMZ file from raw bytes, parses it, stores its
  /// text content and adds it to the route index. Returns the new route's
  /// metadata.
  ///
  /// Throws [DuplicateRouteException] when the same track (by point
  /// fingerprint) is already in the library - callers should open
  /// [DuplicateRouteException.existing] instead of importing again.
  /// Pass [skipDuplicateCheck] for in-app recording saves that may
  /// intentionally snapshot an in-progress ride more than once.
  Future<GpxRoute> importFromBytes({
    required Uint8List bytes,
    required String suggestedFileName,
    int? batteryStartPercent,
    int? batteryEndPercent,
    bool skipDuplicateCheck = false,
  }) async {
    final xml = decodeTrackBytes(bytes, fileName: suggestedFileName);
    // Off the UI isolate - large GPX/KML imports used to freeze the app
    // before the map screen even opened.
    final parsed = await compute(parseTrackXml, xml);
    if (parsed.points.isEmpty) {
      throw const FormatException('Dosyada rota/track noktası bulunamadı.');
    }

    final fingerprint = trackFingerprint(parsed.points);
    if (!skipDuplicateCheck) {
      final existing = _findByFingerprint(fingerprint);
      if (existing != null) {
        throw DuplicateRouteException(existing);
      }
    }

    final id = _uuid.v4();
    // Prefer the file name the user actually gave it: many GPS tracker apps
    // (Garmin, "GPX Tracker", etc.) embed a generic auto-generated name like
    // "Track 219" inside the file's own metadata, which isn't what the user
    // meant when they renamed the file to something meaningful before import.
    final baseName = cleanRouteName(stripTrackExtension(suggestedFileName));
    final name = baseName.isNotEmpty
        ? baseName
        : (parsed.suggestedName?.isNotEmpty == true
              ? cleanRouteName(parsed.suggestedName!)
              : 'Adsız rota');

    final route = buildRouteMetadata(
      id: id,
      name: name,
      importedAt: DateTime.now(),
      parsed: parsed,
      batteryStartPercent: batteryStartPercent,
      batteryEndPercent: batteryEndPercent,
    );

    final box = await _openBox();
    await box.put(_contentKey(id), xml);

    _routes.add(route);
    _sortInPlace();
    await _persistIndex(box);
    notifyListeners();
    return route;
  }

  Future<void> rename(String id, String newName) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _routes[index] = _routes[index].copyWith(name: newName);
    await _persistIndex();
    notifyListeners();
  }

  /// Replaces a route's stored track text and cached stats in place - used
  /// by the route anomaly editor after removing GPS glitch points, so the
  /// edit is actually persisted (not just filtered for display) and the
  /// route's distance/duration/elevation/bounds reflect the cleaned track.
  /// Keeps the same id; [metadata] should otherwise match [id] (same id,
  /// caller's choice of name/importedAt/battery fields).
  Future<void> updateContent({
    required String id,
    required String xml,
    required GpxRoute metadata,
  }) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _routes[index] = metadata;
    _sortInPlace();
    final box = await _openBox();
    await box.put(_contentKey(id), xml);
    await _persistIndex(box);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _routes.removeAt(index);
    final box = await _openBox();
    await box.delete(_contentKey(id));
    await _persistIndex(box);
    notifyListeners();
  }

  Future<String> readTrackContent(GpxRoute route) async {
    final box = await _openBox();
    final content = box.get(_contentKey(route.id));
    if (content == null) {
      throw StateError('Rota içeriği bulunamadı: ${route.name}');
    }
    return content;
  }

  Future<void> _persistIndex([Box<String>? openBox]) async {
    final box = openBox ?? await _openBox();
    await box.put(
      _indexKey,
      jsonEncode(_routes.map((r) => r.toJson()).toList()),
    );
  }
}
