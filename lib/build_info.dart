/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
/// Also the single product-version source: bump together with changelog.dart,
/// web/sw.js APP_VERSION, and web/index.html RIDEATLAS_WEB_VERSION / ?v=
/// (deploy-web.yml restamps the web files from this label).
const String kAppBuildLabel = 'v1.4.85 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Yeni sürüm alt bannerdan güncellenir: Güncelle deyince bir kez yenilenir. '
    'Açılış diyaloğu yok; header’da ikinci bir güncelleme düğmesi yok.';
