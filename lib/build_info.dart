/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.148 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNoteTr =
    'Gün mesafesi artık sürülmüş km (Day Atlas gibi). Çok günlük iz önce '
    'kırmızı; ize dokununca günlere ayrılır. Otomatik durak: eğik çizgi + durak.';

const String kAppBuildNoteEn =
    'Day distance is driven km (Day Atlas–style). Multi-day tracks start red; '
    'tap to split by day. Auto-pause: slash + pause mark on the speed pill.';

/// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
String localizedBuildNote(String languageCode) =>
    languageCode == 'tr' ? kAppBuildNoteTr : kAppBuildNoteEn;
