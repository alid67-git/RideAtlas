/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v0.1.11 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'build_web.bat düzeltildi: "call" eksikti, bu yüzden pub get sonrası '
    'derleme adımı hiç çalışmıyordu. Uygulama tarafında bu sürümde başka '
    'değişiklik yok.';
