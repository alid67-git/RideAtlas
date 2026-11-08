import 'dart:ui' show PlatformDispatcher;

import 'package:hive/hive.dart';

const metaBoxName = 'rideatlas_meta';
const localeCodeKey = 'locale_code';

/// Language the UI should use right now: the rider's saved choice, else the
/// device language when it is tr/en/de, else Turkish (the app default).
///
/// Safe to call without a [BuildContext] — used by Car/Android Auto copy,
/// recording notifications, and fallback route names.
String resolvedLanguageCode() {
  try {
    if (Hive.isBoxOpen(metaBoxName)) {
      final saved = Hive.box<String>(metaBoxName).get(localeCodeKey);
      if (saved != null && saved.isNotEmpty) return saved;
    }
  } catch (_) {}
  final device = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  if (device == 'en' || device == 'de' || device == 'tr') return device;
  return 'tr';
}

String unnamedRouteLabel() {
  switch (resolvedLanguageCode()) {
    case 'en':
      return 'Unnamed route';
    case 'de':
      return 'Unbenannte Route';
    default:
      return 'Adsız rota';
  }
}
