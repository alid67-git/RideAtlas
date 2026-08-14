/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.41 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Bir önceki pil tasarrufu değişikliği duraklama sonrası harekete geçişi '
    'çok geç fark ediyordu (8sn\'ye kadar "Otomatik duraklatıldı" yazısı '
    'kalıyordu). GPS\'in duraklamadaki yenileme aralığı 8sn\'den 3sn\'ye '
    'düşürüldü - pil tasarrufu büyük ölçüde korunuyor, ama harekete geçince '
    'çok daha hızlı fark ediliyor.';
