import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/vehicle_icon.dart';

const _metaBoxName = 'rideatlas_meta';
const _vehicleIconKey = 'vehicle_icon_id'; // legacy, read for migration only
const _categoryKey = 'vehicle_icon_category';
const _colorIndexKey = 'vehicle_icon_color_index';
const _sizeIndexKey = 'vehicle_icon_size_index';

/// Holds the user's chosen "you are here" marker style, persisted in Hive.
/// Vehicle type (classic/motorcycle/car), color and size are picked
/// independently of each other - same pattern as
/// [StatIconSettingsController] - rather than the old single "one of 10
/// preset combos" choice, which bundled a fixed color to a fixed size and
/// didn't let the rider mix and match.
class VehicleIconController extends ChangeNotifier {
  VehicleIconCategory _category = VehicleIconCategory.classic;
  int _colorIndex = 0;
  int _sizeIndex = 1;

  VehicleIconCategory get category => _category;
  int get colorIndex => _colorIndex;
  int get sizeIndex => _sizeIndex;
  double get sizeScale => vehicleIconSizeOptions[_sizeIndex];

  /// The color/size variants available for the current [category] (empty
  /// for [VehicleIconCategory.classic], which has no image).
  List<VehicleIconOption> get colorVariants =>
      kVehicleIconOptions.where((o) => o.category == _category).toList();

  /// Synthesized view combining the three independent choices into the
  /// shape every renderer (map markers, settings preview) already expects -
  /// they stay unaware that color and size are now picked separately.
  VehicleIconOption get option {
    final variants = colorVariants;
    if (variants.isEmpty) return kVehicleIconOptions.first;
    final base = variants[_colorIndex.clamp(0, variants.length - 1)];
    return VehicleIconOption(
      id: base.id,
      category: base.category,
      imageAsset: base.imageAsset,
      scale: sizeScale,
    );
  }

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final categoryStored = box.get(_categoryKey);
    if (categoryStored != null) {
      _category = VehicleIconCategory.values.firstWhere(
        (c) => c.name == categoryStored,
        orElse: () => VehicleIconCategory.classic,
      );
    } else {
      // Migrate a pre-decoupling single-id choice, if one was saved before
      // this version - keeps the rider's existing pick instead of silently
      // resetting them to the classic dot.
      final legacyId = box.get(_vehicleIconKey);
      if (legacyId != null) {
        final legacy = findVehicleIconOption(legacyId);
        _category = legacy.category;
        final variants = kVehicleIconOptions
            .where((o) => o.category == legacy.category)
            .toList();
        final legacyIndex = variants.indexWhere((o) => o.id == legacy.id);
        if (legacyIndex >= 0) _colorIndex = legacyIndex;
      }
    }
    final colorStored = int.tryParse(box.get(_colorIndexKey) ?? '');
    if (colorStored != null) _colorIndex = colorStored;
    final sizeStored = int.tryParse(box.get(_sizeIndexKey) ?? '');
    if (sizeStored != null &&
        sizeStored >= 0 &&
        sizeStored < vehicleIconSizeOptions.length) {
      _sizeIndex = sizeStored;
    }
    notifyListeners();
  }

  Future<void> setCategory(VehicleIconCategory category) async {
    _category = category;
    _colorIndex = 0;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_categoryKey, category.name);
    await box.put(_colorIndexKey, '0');
  }

  Future<void> setColorIndex(int index) async {
    _colorIndex = index;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_colorIndexKey, index.toString());
  }

  Future<void> setSizeIndex(int index) async {
    _sizeIndex = index;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_sizeIndexKey, index.toString());
  }
}
