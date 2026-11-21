/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.165 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Ayarlar’da Arayüz alt menüsü; Gelişmiş kapalıyken gün bazlı içe/dışa aktarma gizlenir.';

const String kAppBuildNoteEn =
    'Settings gains an Interface submenu; Advanced off hides day-based import/export.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
