/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.8 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Devam: bazı telefonlarda (özellikle MIUI gibi agresif pil yönetimi '
    'olanlarda) sistem kaydı yeniden hiç başlatmıyor, sadece öldürüyordu - '
    'önceki düzeltme bu durumu kapsamıyordu. Artık uygulama her açılışta '
    'böyle yarım kalmış bir kayıt olup olmadığını kontrol ediyor ve varsa '
    'otomatik olarak rota listesine kaydediyor.';
