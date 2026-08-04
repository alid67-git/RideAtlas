import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/vehicle_icon.dart';

const _metaBoxName = 'rideatlas_meta';
const _vehicleIconKey = 'vehicle_icon_id';

/// Holds the user's chosen "you are here" marker style, persisted in Hive.
/// Defaults to the classic dot until the user picks something else in
/// Settings.
class VehicleIconController extends ChangeNotifier {
  VehicleIconOption _option = kVehicleIconOptions.first;
  VehicleIconOption get option => _option;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final id = box.get(_vehicleIconKey);
    if (id == null) return;
    _option = findVehicleIconOption(id);
    notifyListeners();
  }

  Future<void> setOption(VehicleIconOption option) async {
    _option = option;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_vehicleIconKey, option.id);
  }
}
