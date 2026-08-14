/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.45 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Bir önceki sürümdeki "sıçrama" filtresi yetersiz kaldı - kullanıcının '
    'gönderdiği gerçek rota dosyasını inceleyince neden anlaşıldı: '
    'sıçrayan noktalar tek başına imkansız bir hız ima etmiyordu (~140 '
    'km/s - hızlı ama "anlık olarak imkansız" eşiğinin altında), üstelik '
    'aynı yerde donup kalan birkaç ölçüm halinde geliyordu - eski hız '
    'sınırı temelli filtre bunu yakalayamıyordu. Yeni bir "gidip-dönme" '
    'algılayıcısı eklendi: rota aniden uzağa sıçrayıp birkaç ölçüm sonra '
    'neredeyse aynı noktaya geri dönüyorsa (gerçek bir sürüş asla '
    'yapmayacağı bir şey), aradaki noktalar artık GPS aksaklığı olarak '
    'tanınıyor. Gerçek dosyadan alınan verilerle test edilip doğrulandı.';
