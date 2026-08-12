/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.21 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Bir sürü küçük düzeltme: gereksiz "geçmiş kaydı kurtarma" özelliği '
    'kaldırıldı (karışıklığa yol açıyordu); anlık duruşlar artık mola '
    'sayılmıyor, sadece 10 dakika ve üzeri duruşlar mola - ortalama hız da '
    'artık sadece sürüş süresine göre hesaplanıyor; kayıt ekranındaki '
    'Süre/Mesafe/Yükseklik kutuları hız büyüdükçe sıkışmasın diye kendi '
    'satırına taşındı; istatistik kartı ikonlarının rengi ve büyüklüğü artık '
    'Ayarlar\'dan seçilebiliyor; özet sayfaları sadeleşti: Maks. hız yanına '
    'son moladan bu yana geçen süre eklendi, tırmanış/iniş/maks-min irtifa '
    'tek satırda yan yana.';
