/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.164 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gün detayında ortalama/maks hız; kartlar uzun basınca sürükle-bırak ve ayardan seçilir.';

const String kAppBuildNoteEn =
    'Day detail adds avg/max speed; long-press drag reorders cards; tune menu shows/hides them.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
