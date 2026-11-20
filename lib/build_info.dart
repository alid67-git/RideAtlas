/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.155 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Sağdaki takvim ikonu ile gün gün görünümü aç/kapat — ize basmana gerek yok.';

const String kAppBuildNoteEn =
    'Right-side calendar icon toggles day-by-day view — no need to tap the track.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
