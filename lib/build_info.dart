/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v0.2.10 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'İçe aktarılan rotanın ismi artık dosya adını önceliyor - GPX/KML '
    'dosyasının içine gömülü genel isimler (ör. "Track 219") artık '
    'senin verdiğin dosya adının önüne geçmiyor. GitHub Pages '
    'derlemesinde service worker de kapatıldı; hâlâ eski badge görürsen '
    'site verilerini temizle veya gizli pencerede aç.';
