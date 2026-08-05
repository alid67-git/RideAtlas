/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.3.44 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Gerçek kök neden bulundu: uygulama şimdiye kadar "Her zaman izin ver" '
    'konum iznini hiç istemiyordu, bu yüzden Ayarlar\'da bu seçenek '
    'görünmüyordu. Artık isteniyor; kayıt başlarken izin sadece "uygulama '
    'kullanılırken" ise Ayarlar\'ı açmanız için bir uyarı çıkıyor. Ayarlar\'a '
    'da doğrudan bir kısayol eklendi.';
