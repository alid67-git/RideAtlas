/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.18 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'KRİTİK düzeltme: hız göstergesi çok gecikmeli görünüyordu ve harita '
    'bazen yanlış yöne dönmüş kalıyordu - gerçek sebep, GPS konumunun hem '
    'kayıt servisinde hem de haritada sadece 5 saniyede bir güncellenmesiydi. '
    'Artık saniyede bir güncelleniyor, hız ve yön çok daha hızlı tepki '
    'veriyor.';
