/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.166 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Uzayan çok günlük kayıtta gün istatistikleri her GPS noktasında tüm rotayı yeniden hesaplamaz.';

const String kAppBuildNoteEn =
    'Long multi-day recordings no longer recompute all day stats on every GPS fix.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
