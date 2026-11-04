import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../l10n/resolved_language.dart';
import '../web/web_locale_sync.dart';

const _metaBoxName = metaBoxName;
const _localeKey = localeCodeKey;

/// Holds the user's chosen app language (tr/en/de), persisted in Hive. Null
/// means "follow the device's language" (falling back to Turkish if the
/// device language isn't one RideAtlas supports).
class LocaleController extends ChangeNotifier {
  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final code = box.get(_localeKey);
    syncWebLocale(code);
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
      syncWebLocale(null);
    } else {
      await box.put(_localeKey, locale.languageCode);
      syncWebLocale(locale.languageCode);
    }
  }
}
