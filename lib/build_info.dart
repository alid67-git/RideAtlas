/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.34 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Aktif sürüş süresi artık durduğunuz anda ekranda donuyor. Tekrar '
    'harekete geçtiğinizde: duraklama 10 dakikanın altındaysa o süre '
    'geriye eklenir, 10 dakika ve üzeriyse mola sayılır. "Son moladan bu '
    'yana" da artık devam eden bir molayı saymıyor - mola bitip tekrar '
    'harekete geçince sıfırdan başlıyor.';
