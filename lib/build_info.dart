/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.4 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Düzeltme: Özet sekmesindeki "Aktif sürüş süresi" ile Günlük '
    'sekmesindeki "Sürüş süresi" farklı sayılar gösterebiliyordu, çünkü '
    'ikisi farklı yöntemle hesaplanıyordu. Artık ikisi de aynı mola '
    'tespitini kullanıyor, sonuçlar tutarlı.';
