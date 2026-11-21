/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.159 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Çok günlük kayıt kaydedilirken varsayılan isim ilk–son gün aralığıdır (ör. 4-21 Kas 2026).';

const String kAppBuildNoteEn =
    'Saving a multi-day recording suggests a first–last date span (e.g. 4-21 Nov 2026).';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
