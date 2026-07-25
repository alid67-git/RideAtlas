import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/gpx_route.dart';
import '../services/gpx_parser.dart';

const _indexPrefsKey = 'rideatlas_routes_index_v1';
const _uuid = Uuid();

String _contentKey(String id) => 'rideatlas_route_content_$id';

/// Owns the set of imported GPX routes: persists their raw GPX text and
/// cached summary stats in [SharedPreferences] so the list screen can render
/// instantly without re-parsing GPX on every launch. Using SharedPreferences
/// (instead of a real file on disk) keeps this working uniformly across
/// mobile, web and desktop - the browser has no real filesystem to write to.
class RouteRepository extends ChangeNotifier {
  final List<GpxRoute> _routes = [];
  bool _loading = true;

  List<GpxRoute> get routes => List.unmodifiable(
    _routes.toList()..sort((a, b) => b.importedAt.compareTo(a.importedAt)),
  );

  bool get isLoading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_indexPrefsKey) ?? const [];
    _routes
      ..clear()
      ..addAll(
        raw.map((s) => GpxRoute.fromJson(jsonDecode(s) as Map<String, dynamic>)),
      );

    _loading = false;
    notifyListeners();
  }

  /// Imports a GPX file from raw bytes, parses it, stores its text content
  /// and adds it to the route index. Returns the new route's metadata.
  Future<GpxRoute> importFromBytes({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    final xml = utf8.decode(bytes, allowMalformed: true);
    final parsed = parseGpxXml(xml);
    if (parsed.points.isEmpty) {
      throw const FormatException('GPX dosyasında rota/track noktası bulunamadı.');
    }

    final id = _uuid.v4();
    final baseName = suggestedFileName.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), '');
    final name = parsed.suggestedName?.isNotEmpty == true ? parsed.suggestedName! : baseName;

    final route = buildRouteMetadata(
      id: id,
      name: name,
      importedAt: DateTime.now(),
      parsed: parsed,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentKey(id), xml);

    _routes.add(route);
    await _persistIndex(prefs);
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

  Future<void> delete(String id) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _routes.removeAt(index);
    await _persistIndex();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_contentKey(id));
  }

  Future<String> readGpxContent(GpxRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final content = prefs.getString(_contentKey(route.id));
    if (content == null) {
      throw StateError('Rota içeriği bulunamadı: ${route.name}');
    }
    return content;
  }

  Future<void> _persistIndex([SharedPreferences? sharedPrefs]) async {
    final prefs = sharedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setStringList(
      _indexPrefsKey,
      _routes.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }
}
