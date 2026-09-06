/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.111 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Kayıt/konum beyaz ekranının gerçek nedeni bulundu ve düzeltildi: '
    'v1.4.109/110\'daki harita karo zamanlama düzeltmeleri yanlış '
    'teşhisti. Asıl sorun, kayıt ekranındaki "kesintiye uğramış kayıt '
    'devam ediyor" bildirimini çizen kod, gösterilecek bir şey yokken '
    'Stack içinde konumlandırılmamış (Positioned olmayan) boş bir widget '
    'döndürüyordu - bu da o Stack\'teki HER ŞEYİN (harita dahil) hiç '
    'çizilmemesine yol açıyordu. Artık her zaman konumlandırılmış bir '
    'widget döndürülüyor.';
