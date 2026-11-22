import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _advancedModeKey = 'advanced_mode_enabled';

/// Settings > "Gelişmiş": when off, day-based import/revise, day-based
/// export, and live track-tap day badges stay hidden. Day viewing (detail
/// sheet, chips, map labels) always works. Defaults to off so the core
/// record / open / full-export path stays simple.
///
/// Stored as '1'/'0' in the shared `Box<String>` `rideatlas_meta` (same
/// constraint as [SatelliteVisibilityController]).
class AdvancedModeController extends ChangeNotifier {
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final stored = box.get(_advancedModeKey);
    if (stored == null) return;
    _enabled = stored == '1';
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_advancedModeKey, enabled ? '1' : '0');
  }
}
