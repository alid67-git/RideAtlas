/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.144 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Devam eden çok günlük kayıtta da haritada gün renkleri, Gün · tarih '
    'etiketleri ve gün detayı; ize dokununca not ekleme seçeneği duruyor.';

const String kAppBuildNoteEn =
    'Ongoing multi-day recordings now show day-colored tracks, Day · date '
    'labels, and day detail; tap the track to add a note from that sheet.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
