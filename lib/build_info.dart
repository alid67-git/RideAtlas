/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.3.40 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Önemli düzeltme: bazı telefonlarda (MIUI, ColorOS, OneUI gibi arayüzlerde) '
    'ekran kapanınca GPS kaydı duruyordu - artık kayıt başlarken ve '
    'Ayarlar > "Arka planda GPS izni" ile uygulamayı pil optimizasyonundan '
    'muaf tutmanız istenecek.';
