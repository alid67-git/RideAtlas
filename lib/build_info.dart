/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.20 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'GPS hız/yön gecikmesine farklı bir çözüm: bir telefonun GPS çipi zaten '
    'saniyede birden hızlı ölçüm üretemiyor, bu yüzden aralığı daha da '
    'kısaltmak yerine hız rakamı ve harita kamerası artık her yeni ölçüm '
    'geldiğinde sürekli, akıcı bir animasyonla o değere doğru kayıyor - '
    'donup birden zıplamak yerine hep hareket hâlinde görünüyor.';
