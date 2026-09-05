/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.96 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'iPhone/Safari\'de GPX seçilip de içeri eklenmediği bildirimi üzerine '
    'web dosya seçicisindeki bir yarış durumu düzeltildi: yavaş bir '
    'okumada iki farklı mekanizma aynı dosyayı aynı anda okumaya '
    'çalışabiliyor, bu sessizce başarısız olup hiçbir hata göstermeden '
    '"hiçbir şey seçilmemiş" gibi davranabiliyordu. Artık okunamayan bir '
    'dosya da fark edilip kullanıcıya bildiriliyor, sessizce '
    'yok sayılmıyor.';
