import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';

/// Hive key for which saved tracks are currently *visible* as map overlays.
///
/// Product rule (keep this): the rider can show some tracks and hide others
/// (home track menu / multi-route picker / recording overlay). That partial
/// show/hide set must survive process death — closing and reopening the app
/// restores the same visible IDs (minus any routes deleted in the meantime).
/// An empty stored value means "hide all" on purpose, not "unset".
const kVisibleTrackIdsKey = 'visible_overlay_route_ids';

/// Loads the persisted visible-track id set. Returns null when the rider has
/// never chosen a show/hide set on this install (callers should leave overlays
/// empty then). Returns an empty set when they explicitly hid everything.
Future<Set<String>?> loadVisibleTrackIds() async {
  final box = await Hive.openBox<String>(_metaBoxName);
  if (!box.containsKey(kVisibleTrackIdsKey)) return null;
  final raw = box.get(kVisibleTrackIdsKey) ?? '';
  if (raw.isEmpty) return <String>{};
  return {
    for (final id in raw.split(','))
      if (id.isNotEmpty) id,
  };
}

/// Persists which tracks should stay visible across app restarts.
Future<void> saveVisibleTrackIds(Iterable<String> ids) async {
  final box = await Hive.openBox<String>(_metaBoxName);
  await box.put(kVisibleTrackIdsKey, ids.join(','));
}
