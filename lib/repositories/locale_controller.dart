import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

const _metaBoxName = 'rideatlas_meta';
const _localeKey = 'locale_code';

/// Holds the user's chosen app language (tr/en/de), persisted in Hive. Null
/// means "follow the device's language" (falling back to Turkish if the
/// device language isn't one RideAtlas supports).
class LocaleController extends ChangeNotifier {
  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final code = box.get(_localeKey);
    if (code == null) return;
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    if (locale == null) {
      await box.delete(_localeKey);
    } else {
      await box.put(_localeKey, locale.languageCode);
    }
  }
}
