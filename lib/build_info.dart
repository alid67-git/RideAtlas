/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.51 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Uzun kayıtlarda uygulamanın kendi kendine kapandığı bildirildi. Kök '
    'sebep bulundu: "Mesafe" değeri her GPS güncellemesinde (saniyede '
    'bir), o ana kadarki TÜM rota noktaları yeniden toplanarak '
    'hesaplanıyordu - kayıt uzadıkça bu hesap da katlanarak ağırlaşıyordu '
    '(binlerce nokta biriktiğinde saniyede binlerce mesafe hesabına '
    'çıkıyordu). Çok saatlik bir kayıtta bu, ekranın donmasına ve '
    'uygulamanın kapanmasına yol açacak kadar ağırlaşabiliyordu. Mesafe '
    'artık her yeni nokta geldiğinde tek seferlik eklenerek tutuluyor, '
    'baştan yeniden hesaplanmıyor - kayıt ne kadar uzarsa uzasın her '
    'güncelleme aynı hızda kalıyor.';
