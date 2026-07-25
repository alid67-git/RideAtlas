import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/gpx_route.dart';
import '../services/gpx_parser.dart';

const _indexPrefsKey = 'rideatlas_routes_index_v1';
const _uuid = Uuid();

/// Owns the set of imported GPX routes: persists their raw files under the
/// app's documents directory and caches their summary stats (as JSON) in
/// [SharedPreferences] so the list screen can render without re-parsing GPX
/// on every launch.
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

  Future<Directory> _routesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'routes'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Imports a GPX file from raw bytes, parses it, stores a copy on disk and
  /// adds it to the route index. Returns the new route's metadata.
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
    final dir = await _routesDir();
    final fileName = '$id.gpx';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    final baseName = p.basenameWithoutExtension(suggestedFileName);
    final name = parsed.suggestedName?.isNotEmpty == true ? parsed.suggestedName! : baseName;

    final route = buildRouteMetadata(
      id: id,
      name: name,
      filePath: file.path,
      importedAt: DateTime.now(),
      parsed: parsed,
    );

    _routes.add(route);
    await _persistIndex();
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
    final route = _routes[index];
    _routes.removeAt(index);
    await _persistIndex();
    notifyListeners();

    final file = File(route.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> readGpxContent(GpxRoute route) {
    return File(route.filePath).readAsString();
  }

  Future<void> _persistIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _indexPrefsKey,
      _routes.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }
}
