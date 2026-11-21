/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.161 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Kayıt kaydedilince hemen “Nereye?” sorulur (klasör / paylaş); galeri taramasından önce.';

const String kAppBuildNoteEn =
    'After saving a recording, “Where?” is asked right away (folder / share), before gallery scan.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
