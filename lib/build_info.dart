/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.115 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Ana ekranda "Rota seç..." ile birden fazla iz seçmek artık ayrı bir '
    'haritaya götürmüyor - kayıt ekranındaki referans iz mantığı gibi, '
    'seçilen izler doğrudan ana ekranın kendi haritasının üzerine çiziliyor '
    've hafızaya yazılıyor; uygulama kapanıp açılsa bile aynı izler orada '
    'olacak. Tek rota seçilirse (veya tek dosya içe aktarılırsa) otomatik '
    'olarak o rotanın tam detay/analiz ekranına gidiliyor. Çoklu izlerden '
    'birine haritada dokununca ismi ve "Detaylı analiz" butonu çıkıyor. '
    'Ayrıca gerçek bir hata düzeltildi: daha önce, gösterilen tüm izlerin '
    'işaretini kaldırıp onaylayınca bu "boş" seçim hafızaya hiç '
    'yazılmıyordu - ekran tekrar açıldığında eski (kaldırılmış) seçim geri '
    'geliyordu. Şimdi boş seçim de bilerek "gizle" olarak kabul ediliyor '
    've doğru şekilde hatırlanıyor.';
