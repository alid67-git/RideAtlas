/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.154 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Dışa aktarmada tekrar isim sorulmaz; “Nereye?” her zaman görünür (klasör / paylaş).';

const String kAppBuildNoteEn =
    'Export no longer asks for a name again; “Where?” stays visible (folder / share).';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
