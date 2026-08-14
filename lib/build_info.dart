/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.42 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Mola sonrası bazen "Otomatik duraklatıldı" yazısı hiç kapanmıyordu - '
    'sadece geç değil, gerçekten takılı kalıyordu. Sebep: duraklama '
    'sırasında GPS, pil tasarrufu için düşük hassasiyetli konum '
    'kaynağına (WiFi/baz istasyonu) geçebiliyordu; bu kaynak çoğu zaman '
    'hız bilgisi vermiyor, o yüzden gerçekten hareket etmeye başlasanız '
    'bile ölçülen hız sıfıra yakın kalıp duraklamayı hiç sonlandırmıyordu. '
    'Duraklama sırasında da GPS çipi kullanılmaya devam edilecek şekilde '
    'düzeltildi (pil tasarrufu yenileme aralığından geliyor zaten) - artık '
    'harekete geçince gerçek hız ölçülüp duraklama güvenilir şekilde '
    'kapanıyor.';
