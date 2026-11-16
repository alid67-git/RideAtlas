/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.141 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Çok günlük dışa aktarmada “Seçili günler” altında gün listesi (1., 2., …) '
    'yine görünür; kaydırarak işaretleyin.';

const String kAppBuildNoteEn =
    'On multi-day export, the day checklist (day 1, 2, …) shows again under '
    '“Selected days”; scroll and tick the ones you want.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
