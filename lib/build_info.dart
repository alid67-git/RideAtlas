/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.145 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gün detayında önce 1. gün; sağ/sol ile gezinme, o günün rotası mini '
    'haritada; haritaya dokununca büyük ekran ve üst/alt bilgi.';

const String kAppBuildNoteEn =
    'Day detail opens on Day 1; left/right to browse, that day’s route on a '
    'mini map; tap for fullscreen map with stats overlay.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
