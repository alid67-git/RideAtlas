/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.3 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Önemli düzeltme: "Aktif sürüş süresi" bazı rotalarda "Toplam süre" ile '
    'aynı çıkıyordu (Mola süresi de hep 0 görünüyordu) - artık noktalar '
    'arası gerçek hıza bakarak hesaplanıyor, duran ama yine de düzenli '
    'aralıklarla kayıt yapmaya devam eden cihazlardan gelen rotalarda da '
    'doğru sonuç veriyor.';
