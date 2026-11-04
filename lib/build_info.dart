/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.130 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Dil İngilizceyken sürüm geçmişi, yenilikler penceresi ve kalan sabit '
    'Türkçe metinler (Android Auto, kayıt bildirimi, analiz ilerleme) İngilizce.';

const String kAppBuildNoteEn =
    'With English selected, version history, the what’s-new dialog, and leftover '
    'hardcoded copy (Android Auto, the recording notification, analysis progress) '
    'are now English too.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
