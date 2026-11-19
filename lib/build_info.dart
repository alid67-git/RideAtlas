/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.153 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gün detayında yükle ikonu / “Bu günü GPX ile revize et” ile o günü değiştirebilirsin.';

const String kAppBuildNoteEn =
    'On day detail, use the upload icon / “Revise this day from GPX” to replace that day.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
