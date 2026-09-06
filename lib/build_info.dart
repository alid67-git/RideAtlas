/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.112 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'GPX içe aktarma bazen sessizce hiçbir şey yapmıyordu: tarayıcının '
    'dosya seçme penceresinde "cancel" olayı, gerçekten bir dosya '
    'seçilmiş olsa bile "change" olayından önce (ve varsayılan '
    'gecikmeden daha uzun bir farkla) tetiklenebiliyordu; bu da seçimi '
    'sessizce "hiçbir şey seçilmedi" sayıp yutuyordu. Artık sabit bir '
    'gecikme yerine, gerçek seçim gelene kadar (en fazla ~2sn) kontrol '
    'tekrarlanıyor. Ayrıca kayıt ekranının gezinme akışı sadeleştirildi: '
    'artık tek geri tuşu yok, üstteki geri oku kaldırıldı; yeni bir '
    'kayıt başlatıldığında her zaman Veri sayfasında açılıyor, devam '
    'eden bir kayda dönüldüğünde ise en son hangi sayfada kalındıysa '
    'orada açılıyor; gösterilen referans izler de hatırlanıp bir sonraki '
    'açılışta otomatik olarak geri getiriliyor.';
