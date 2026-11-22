/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.168 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gelişmiş gün rozeti düzeltildi: dokunuş yanıt veriyor; uzun kayıtlarda harita daha akıcı.';

const String kAppBuildNoteEn =
    'Advanced day-badge tap fixed; long multi-day live maps stay smoother.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
