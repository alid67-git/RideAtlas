/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.142 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Dışa aktarılan dosya adı artık kaydettiğiniz anın tarihi değil; GPS’teki '
    'kayıt gününün tarihi (RideAtlas_yyyy-MM-dd).';

const String kAppBuildNoteEn =
    'Exported file names now use each track’s calendar day '
    '(RideAtlas_yyyy-MM-dd), not the date you tapped Save.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
