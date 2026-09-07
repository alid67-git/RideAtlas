/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.113 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Ana ekrandaki rota menüsü sadeleştirildi: "Tümünü göster" ve "Rotalar" '
    'listesi kaldırıldı (Hepsi seçeneği zaten "Rota seç..." penceresinde '
    'vardı), sol üstteki rota ikonu yerine "Rotalar" yazısı kondu. Rota '
    'yeniden adlandırma/birleştirme/silme artık Ayarlar > Rotalar\'dan '
    'erişiliyor. İzleri gösteren harita (Rota seç... ile açılan ekran) '
    'artık en son hangi izler gösteriliyorduysa onları hatırlıyor: "Rota '
    'seç..." penceresi son seçimi işaretli açıyor, aynı seçimle tekrar '
    'açıldığında da kapanmadan önceki zoom/konuma dönüyor - sanki hiç '
    'kapanmamış gibi.';
