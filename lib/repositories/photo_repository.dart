import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/route_photo.dart';

const _indexBoxName = 'rideatlas_photos';
const _bytesBoxName = 'rideatlas_photo_bytes';
const _indexKey = 'index';
const _uuid = Uuid();

/// Owns photos attached to routes. Mirrors [RouteRepository]'s split between
/// a small JSON index (metadata) and a separate box for the much larger raw
/// bytes, so listing/filtering photos never has to touch image data.
class PhotoRepository extends ChangeNotifier {
  final List<RoutePhoto> _photos = [];
  final Map<String, Uint8List> _bytesCache = {};
  bool _loading = true;
  Box<String>? _indexBox;
  Box<Uint8List>? _bytesBox;

  bool get isLoading => _loading;

  /// Synchronous access to an already-fetched photo's bytes, for widgets
  /// that watch this repository and rebuild once [loadBytes] resolves.
  Uint8List? cachedBytes(String photoId) => _bytesCache[photoId];

  /// Fetches and caches a photo's bytes if not already cached, notifying
  /// listeners once available so [cachedBytes] reflects the result.
  Future<Uint8List?> loadBytes(String photoId) async {
    final cached = _bytesCache[photoId];
    if (cached != null) return cached;
    final box = await _openBytesBox();
    final bytes = box.get(photoId);
    if (bytes != null) {
      _bytesCache[photoId] = bytes;
      notifyListeners();
    }
    return bytes;
  }

  List<RoutePhoto> photosFor(String routeId) {
    final list = _photos.where((p) => p.routeId == routeId).toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return list;
  }

  Future<Box<String>> _openIndexBox() async =>
      _indexBox ??= await Hive.openBox<String>(_indexBoxName);

  Future<Box<Uint8List>> _openBytesBox() async =>
      _bytesBox ??= await Hive.openBox<Uint8List>(_bytesBoxName);

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final box = await _openIndexBox();
    final raw = box.get(_indexKey);
    final list = raw == null ? const [] : jsonDecode(raw) as List<dynamic>;
    _photos
      ..clear()
      ..addAll(
        list.map((e) => RoutePhoto.fromJson(e as Map<String, dynamic>)),
      );

    _loading = false;
    notifyListeners();
  }

  Future<RoutePhoto> add({
    required String routeId,
    required Uint8List bytes,
    double? lat,
    double? lng,
  }) async {
    final photo = RoutePhoto(
      id: _uuid.v4(),
      routeId: routeId,
      addedAt: DateTime.now(),
      lat: lat,
      lng: lng,
    );

    final bytesBox = await _openBytesBox();
    await bytesBox.put(photo.id, bytes);
    _bytesCache[photo.id] = bytes;

    _photos.add(photo);
    await _persistIndex();
    notifyListeners();
    return photo;
  }

  Future<void> delete(String photoId) async {
    final index = _photos.indexWhere((p) => p.id == photoId);
    if (index == -1) return;
    _photos.removeAt(index);
    _bytesCache.remove(photoId);
    final bytesBox = await _openBytesBox();
    await bytesBox.delete(photoId);
    await _persistIndex();
    notifyListeners();
  }

  Future<void> deleteForRoute(String routeId) async {
    final ids = _photos.where((p) => p.routeId == routeId).map((p) => p.id);
    final bytesBox = await _openBytesBox();
    for (final id in ids) {
      await bytesBox.delete(id);
      _bytesCache.remove(id);
    }
    _photos.removeWhere((p) => p.routeId == routeId);
    await _persistIndex();
    notifyListeners();
  }

  Future<void> _persistIndex() async {
    final box = await _openIndexBox();
    await box.put(
      _indexKey,
      jsonEncode(_photos.map((p) => p.toJson()).toList()),
    );
  }
}
