import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/gpx_route.dart';
import '../services/gpx_parser.dart';

const _boxName = 'rideatlas_routes';
const _indexKey = 'index';
const _uuid = Uuid();

String _contentKey(String id) => 'content_$id';

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

  List<GpxRoute> get routes => List.unmodifiable(
    _routes.toList()..sort((a, b) => b.importedAt.compareTo(a.importedAt)),
  );

  bool get isLoading => _loading;

  Future<Box<String>> _openBox() async {
    return _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final box = await _openBox();
    final raw = box.get(_indexKey);
    final list = raw == null ? const [] : jsonDecode(raw) as List<dynamic>;
    _routes
      ..clear()
      ..addAll(list.map((e) => GpxRoute.fromJson(e as Map<String, dynamic>)));

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

    final box = await _openBox();
    await box.put(_contentKey(id), xml);

    _routes.add(route);
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

  Future<void> delete(String id) async {
    final index = _routes.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _routes.removeAt(index);
    final box = await _openBox();
    await box.delete(_contentKey(id));
    await _persistIndex(box);
    notifyListeners();
  }

  Future<String> readGpxContent(GpxRoute route) async {
    final box = await _openBox();
    final content = box.get(_contentKey(route.id));
    if (content == null) {
      throw StateError('Rota içeriği bulunamadı: ${route.name}');
    }
    return content;
  }

  Future<void> _persistIndex([Box<String>? openBox]) async {
    final box = openBox ?? await _openBox();
    await box.put(_indexKey, jsonEncode(_routes.map((r) => r.toJson()).toList()));
  }
}
