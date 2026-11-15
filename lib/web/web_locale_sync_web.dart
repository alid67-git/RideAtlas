import 'package:web/web.dart' as web;

const _storageKey = 'rideatlas_locale';

/// Mirrors the in-app language into localStorage so [web/app_update.js]
/// can localize the update banner with the rider's choice, not only the
/// browser language.
void syncWebLocale(String? code) {
  try {
    if (code == null || code.isEmpty) {
      web.window.localStorage.removeItem(_storageKey);
    } else {
      web.window.localStorage.setItem(_storageKey, code);
    }
  } catch (_) {}
}
