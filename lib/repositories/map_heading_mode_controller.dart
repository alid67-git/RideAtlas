import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _headingUpKey = 'record_map_heading_up';

/// Whether [RecordScreen]'s map defaults to course-up ("heading up", like a
/// turn-by-turn navigation app) instead of north-up. Defaults to true -
/// most riders expect the map to point the way they're driving, the way
/// every normal navigation app behaves. Persisted so the choice, once made
/// (see the recenter button's north-up/course-up toggle), survives to the
/// next recording session instead of resetting every time.
///
/// Stored as a string ('1'/'0') rather than a bool because the shared
/// `rideatlas_meta` Hive box is already opened elsewhere (see
/// [VehicleIconController], [LocaleController]) as a `Box<String>` - Hive
/// requires every open of the same box name to agree on the value type.
class MapHeadingModeController extends ChangeNotifier {
  bool _headingUp = true;
  bool get headingUp => _headingUp;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final stored = box.get(_headingUpKey);
    if (stored == null) return;
    _headingUp = stored == '1';
    notifyListeners();
  }

  Future<void> setHeadingUp(bool headingUp) async {
    _headingUp = headingUp;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_headingUpKey, headingUp ? '1' : '0');
  }
}
