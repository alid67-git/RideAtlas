import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _statIconColorIndexKey = 'stat_icon_color_index';
const _statIconSizeIndexKey = 'stat_icon_size_index';

/// Fixed palette for [AnalysisStatCard]'s icons - a small, curated set
/// rather than a full color wheel, matching the app's existing vehicle-icon
/// picker pattern. Index 0 is the app's long-standing single blue accent.
const List<Color> statIconColorOptions = [
  Color(0xFF4FA3FF), // blue (default)
  Color(0xFFEF5350), // red
  Color(0xFFFFA726), // orange
  Color(0xFF66BB6A), // green
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // teal
];

/// Icon size multipliers applied on top of [AnalysisStatCard]'s own base
/// icon size (20/26 logical px depending on card density).
const List<double> statIconSizeOptions = [0.8, 1.0, 1.2, 1.4, 1.6];

/// User-chosen color + size for every stat card icon across the app
/// (record screen's info page, saved-route summary page, analysis sheet) -
/// previously fixed per-screen, now picked once in Settings and applied
/// everywhere so the icons read consistently and riders who want them
/// bigger/differently colored don't need a code change to get that.
class StatIconSettingsController extends ChangeNotifier {
  int _colorIndex = 0;
  int _sizeIndex = 1;

  Color get color => statIconColorOptions[_colorIndex];
  double get sizeScale => statIconSizeOptions[_sizeIndex];
  int get colorIndex => _colorIndex;
  int get sizeIndex => _sizeIndex;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final colorStored = int.tryParse(box.get(_statIconColorIndexKey) ?? '');
    if (colorStored != null &&
        colorStored >= 0 &&
        colorStored < statIconColorOptions.length) {
      _colorIndex = colorStored;
    }
    final sizeStored = int.tryParse(box.get(_statIconSizeIndexKey) ?? '');
    if (sizeStored != null &&
        sizeStored >= 0 &&
        sizeStored < statIconSizeOptions.length) {
      _sizeIndex = sizeStored;
    }
    notifyListeners();
  }

  Future<void> setColorIndex(int index) async {
    _colorIndex = index;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_statIconColorIndexKey, index.toString());
  }

  Future<void> setSizeIndex(int index) async {
    _sizeIndex = index;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_statIconSizeIndexKey, index.toString());
  }
}
