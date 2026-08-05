import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _satelliteVisibilityKey = 'satellite_count_visible';

/// Whether the small "N satellites" indicator (see SatelliteCountBadge)
/// should be shown at all - Settings > "Uydu sayısını göster" lets the user
/// turn it off. Defaults to visible.
///
/// Stored as a string ('1'/'0') rather than a bool because the shared
/// `rideatlas_meta` Hive box is already opened elsewhere (see
/// [VehicleIconController], [LocaleController]) as a `Box<String>` - Hive
/// requires every open of the same box name to agree on the value type.
class SatelliteVisibilityController extends ChangeNotifier {
  bool _visible = true;
  bool get visible => _visible;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final stored = box.get(_satelliteVisibilityKey);
    if (stored == null) return;
    _visible = stored == '1';
    notifyListeners();
  }

  Future<void> setVisible(bool visible) async {
    _visible = visible;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_satelliteVisibilityKey, visible ? '1' : '0');
  }
}
