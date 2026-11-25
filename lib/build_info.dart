/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.171 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Zaman damgasız feribot gidiş-dönüş (Koh Lipe vb.) artık haritadan silinmez.';

const String kAppBuildNoteEn =
    'Untimed ferry round-trips (e.g. Koh Lipe) are no longer wiped from the map.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
