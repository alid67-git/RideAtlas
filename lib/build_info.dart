/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.12 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Düzeltme: haritanın yön-yukarı dönüşü dönemeçlerde gerçek yöne geç '
    'yetişiyordu (önceki titreme düzeltmesi, son birkaç okumayı ortalayarak '
    'gecikmeye yol açmıştı). Artık gerçek dönüşler anında uygulanıyor, '
    'sadece imkansız ani sıçramalar göz ardı ediliyor.';
