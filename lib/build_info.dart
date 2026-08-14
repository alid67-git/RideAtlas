/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.44 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Rota Analiz > Özet sekmesindeki "Ortalama hız", "Aktif sürüş süresi" '
    'ile aynı anda ekranda dururken tamamen farklı bir yöntemle '
    'hesaplanıyordu (biri >=10dk\'lık molaları çıkarıyordu, diğeri '
    '1km/s altındaki her segmenti tamamen yok sayıyordu) - bir kullanıcı '
    'bunu başka bir GPX programıyla karşılaştırınca fark etti. Artık ikisi '
    'aynı süreyi kullanıyor, sayfadaki rakamlar birbiriyle tutarlı. Ayrıca: '
    'tek bir kötü GPS noktasından kaynaklanan haritadaki "sıçrama" artık (1) '
    'harita/istatistiklerde otomatik olarak yok sayılıyor, ve (2) "Rotalar" '
    'listesindeki ⋮ menüsüne eklenen "Anormal noktaları düzenle" ile '
    'kalıcı olarak rotadan silinebiliyor.';
