/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.146 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Ruta ile gün şeridi aç/kapa; otomatik duraklatma artık hız kartının '
    'üzerinde şeffaf, net bir yazı olarak görünür.';

const String kAppBuildNoteEn =
    'Tap Ruta to show/hide the day chip strip; auto-pause is a clear '
    'translucent overlay on the speed card.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
