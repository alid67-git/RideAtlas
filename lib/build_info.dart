/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.147 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Güncelleme indirirken “yanıt vermiyor” (ANR) donması giderildi: APK '
    'arka planda iner, arayüz kilitlenmez.';

const String kAppBuildNoteEn =
    'Fixed “app isn’t responding” freezes while updating: the APK downloads '
    'in the background so the UI stays responsive.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
