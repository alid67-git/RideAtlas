/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.162 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Kayıt onayında isim + nereye; Ayarlar yedeği yalnızca gerçek yazmada “çalışıyor” gösterir.';

const String kAppBuildNoteEn =
    'Save confirm shows name + where; Settings backup says “working” only during a real write.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
