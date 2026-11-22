/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.167 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gelişmiş: çok günlük canlı çizgiye dokununca gün rozeti; rozete basınca sadece o gün.';

const String kAppBuildNoteEn =
    'Advanced: tap the multi-day live track for a day badge; tap the badge to show only that day.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
