/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.11 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Düzeltme: GPS bazen fiziksel olarak imkansız ani hız sıçramaları '
    'gösterebiliyordu (ör. 100 km/s\'ten aniden 200 km/s\'e). Artık böyle '
    'sıçramalar hem anlık hız göstergesinde hem de hız grafiği/istatistik '
    'hesaplamalarında göz ardı ediliyor.';
