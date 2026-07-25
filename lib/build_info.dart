/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v0.2.1 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'build_web.bat artık --pwa-strategy=none ile derliyor: Flutter\'ın '
    'service worker önbelleklemesi kapatıldı, böylece yeni bir derleme '
    'sonrası eski sürümün tarayıcıda takılı kalması sorunu çözülüyor.';
