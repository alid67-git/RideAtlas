/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v0.3.0 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Analiz artık sekmeli: Özet, Yükseklik, Güzergâh (ülkeler), Molalar '
    've Hava. Ülke/şehir için reverse geocode, molalar GPS duraklarından, '
    'hava Open-Meteo arşivinden (internet gerekir; sonuçlar önbelleğe alınır).';
