/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.131 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Samsung’da alt sistem çubuğu (geri / açık uygulamalar) ikonların altına '
    'binmiyor: arayüz MedyaAtlas’taki gibi yukarı alındı. Harita (i) kimliği '
    'de seçilen dilde (İngilizceyse English).';

const String kAppBuildNoteEn =
    'On Samsung, map icons no longer sit on the system back/recents bar — the '
    'UI is lifted like MedyaAtlas. Tapping the map (i) credit also follows the '
    'selected language.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
