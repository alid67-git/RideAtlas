/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.90 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'GPX dosyaları artık içe aktarma ekranında reddedilmiyor: dosya seçici '
    'artık işletim sistemi düzeyinde uzantıya göre filtrelemiyor (bazı '
    'Android cihazlarda "gpx" için tanımlı bir dosya türü olmadığından bu '
    'dosyalar listeden gizleniyordu) - .gpx, .kml ve .kmz artık aynı şekilde '
    'seçilebiliyor.';
