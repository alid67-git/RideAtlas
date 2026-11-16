/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.143 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Çok günlük rotalarda haritada Gün 1 · tarih etiketleri; ize veya '
    'etikete dokununca o günün km ve detay sayfası açılır.';

const String kAppBuildNoteEn =
    'Multi-day routes show Day 1 · date labels on the map; tap the track '
    'or label for that day’s km and detail sheet.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
