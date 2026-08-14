/// Bumped by hand on every push so the running build can be eyeballed on
/// screen (Chrome tabs / dev servers can otherwise silently serve stale JS).
const String kAppBuildLabel = 'v1.4.43 beta';

/// Shown once, in a dialog, the first time this build label is seen.
const String kAppBuildNote =
    'Bir önceki sürümdeki düzeltme yeterli değilmiş - kullanıcı gerçek bir '
    'sürüşte yine takılı kaldığını bildirdi. Asıl sebep bulundu: '
    'duraklama sırasında Android tarafındaki konum servisi gelen her GPS '
    'sinyalini tamamen yok sayıyordu (tek satırlık bir "if duraklatılmışsa '
    'çık" kontrolü yüzünden) - yani harekete geçtiğinizde bile uygulamaya '
    'HİÇBİR yeni konum ulaşmıyordu, dolayısıyla "hızı kontrol et, '
    'duraklamayı kaldır" mantığı hiç çalışma fırsatı bulamıyordu. Sadece '
    'elle duraklat/devam ettirdiğinizde çalışması bundandı - o buton konum '
    'beklemeden direkt devam ettiriyor. Artık duraklama sırasında da her '
    'GPS sinyali uygulamaya ulaşıyor (rotaya kaydedilmiyor, sadece hız '
    'kontrolü için kullanılıyor) - otomatik duraklama artık kendi kendine '
    'gerçekten kapanmalı.';
