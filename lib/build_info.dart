/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.149 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gün detayı ve büyük haritada kapat (×) kendi ekranının sol üstünde.';

const String kAppBuildNoteEn =
    'Day detail and full map each have their close (×) at that screen’s top left.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
