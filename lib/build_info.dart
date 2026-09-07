/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.116 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'İki eksiklik giderildi. Kayıt ekranında, kayıt sürerken ana harita '
    'ekranına dönecek görünür bir tuş yoktu (sistem geri tuşu/hareketi hâlâ '
    'çalışıyordu ama iOS\'ta bunun güvenilir bir karşılığı yok) - harita '
    'sayfasının sol üstüne geri oku eklendi, kayıt arka planda devam '
    'ediyor. Ana ekranda da, birden fazla iz üzerine çizildiğinde onlara '
    'tekrar sığdıracak bir tuş yoktu, uzaklaşıp/yakınlaştıktan sonra '
    'manuel geri dönmek gerekiyordu - sağ alta izler gösteriliyorken '
    'çıkan bir "sığdır" tuşu eklendi.';
