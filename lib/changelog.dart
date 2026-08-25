/// Full version history, shown in Settings > About.
///
/// Keep this in sync with [kAppBuildLabel]/[kAppBuildNote] in build_info.dart:
/// every time those are bumped for a push, add a new entry here too (newest
/// first). Notes are intentionally Turkish-only, like the build note itself -
/// this is a developer-facing changelog, not translated UI copy.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.note,
  });

  final String version;

  /// ISO date (yyyy-MM-dd) this version was pushed.
  final String date;
  final String note;
}

const kChangelog = <ChangelogEntry>[
  ChangelogEntry(
    version: 'v1.4.55 beta',
    date: '2026-08-25',
    note:
        'Kayıt kontrolleri yeniden düzenlendi: kayıt sırasında tek tuş '
        '(Duraklat); duraklatınca Devam / Kaydet / Sıfırla. Kaydet oturumu '
        'bitirmez - kayıt sonrası "devam et veya sıfırla" seçilir; '
        'kaydedilmişse sıfırlama uyarısız, kaydedilmemiş veri varsa onay '
        'sorulur. Harita sayfasına "tüm kaydı göster" tuşu eklendi (kuzey '
        'yukarı, tüm rota ekrana sığar); konum tuşu o anki pozisyona ve '
        'course-up takibe döndürür. Haritanın "yukarı gidip aşağı akma" '
        'titremesi çözüldü: araç işareti artık kamerayla aynı animasyonda '
        'ilerliyor (fix gelince öne zıplayıp geri akmıyor) ve her fixte '
        'birikip CPU yakan eski animasyon dinleyicileri temizleniyor. '
        'Ayrıca idle haritada konuma ortalama/takip onarıldı.',
  ),
  ChangelogEntry(
    version: 'v1.4.54 beta',
    date: '2026-08-23',
    note:
        'Kayıt devamı tamamlandı: sadece "kayıt/pause" bayrağı değil, '
        'başlangıç saati, tamamlanmış molalar ve süren duraklatma anı da '
        'diskte saklanıyor. Yeniden açılışta mesafe (tüm GPS noktalarından), '
        'son konum, aktif/duraklatılmış mod ve süreler kaldığı yerden '
        'geliyor. Kayıt yokken (idle) dosya yazılmaz - açılışta kayıt '
        'başlamaz. v1.4.53\'teki 2 sn GPS ve course-up düzeltmeleri duruyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.53 beta',
    date: '2026-08-23',
    note:
        'Kayıt stabilitesi: (1) Uygulama kilitlenince / yanlışlıkla '
        'kapanınca / OEM öldürünce kayıt oturumu diskte saklanıyor; tekrar '
        'açılışta Motion GPX gibi kaldığı yerden devam ediyor (kayıttaysa '
        'kayıt, duraklatılmışsa duraklatılmış; idle ise idle). Eski '
        '"açılışta yetim noktaları sil" davranışı kaldırıldı. (2) Aktif '
        'GPS aralığı 1 sn → 2 sn; harita konum akışı ve native poll de '
        'uyumlandı - saniyelik çift GPS yükü telefonu yoruyordu. (3) '
        'Kayıt bilgi sayfasındayken harita Offstage ile bağlı kalıyor; '
        'haritaya geçince course-up (yön yukarı) yeniden etkin - önceki '
        'MapController kopması giderildi.',
  ),
  ChangelogEntry(
    version: 'v1.4.52 beta',
    date: '2026-08-22',
    note:
        'Kayıt rakımı düzeltildi. Android GPS Location.altitude WGS84 '
        'elipsoid yüksekliği verir; birçok uygulama deniz seviyesi (MSL / '
        'ortometrik) gösterir - fark geoid undülasyonu yüzünden bölgeye '
        'göre genelde 20–40 m. Kullanıcı başka programda ~5 m görürken '
        'RideAtlas\'ta −29 m (yaklaşık 25 m düşük) bildirdi. '
        'RecordingLocationService artık AltitudeConverterCompat ile her '
        'fixi MSL\'e çeviriyor; dönüşüm başarısız olursa eski elipsoid '
        'değerine düşülüyor. Canlı yükseklik, min/maks irtifa, tırmanış/'
        'iniş ve kaydedilen GPX aynı düzeltilmiş rakımı kullanır.',
  ),
  ChangelogEntry(
    version: 'v1.4.51 beta',
    date: '2026-08-15',
    note:
        'Kullanıcı "kayıt yaparken sık sık kendi kendine kapanıyor" diye '
        'bildirdi (özellikle uzun sürüşlerde, tam da o gün üzerinde '
        'çalıştığımız 10+ saatlik/36.628 noktalık örnek gibi). Kod '
        'incelemesinde kök sebep bulundu: GpsRecorder.distanceKm getter\'ı '
        'her okunduğunda TÜM nokta listesini baştan toplayarak mesafeyi '
        'yeniden hesaplıyordu, ve kayıt ekranı bu değeri her GPS '
        'güncellemesinde (saniyede bir) okuyordu - kayıt uzadıkça bu iş '
        'katlanarak ağırlaşıyordu (klasik O(n²) davranış): birkaç saat '
        'sonra saniyede binlerce mesafe hesabına çıkıp ekranı '
        'dondurabiliyor, bu da uygulamanın "kapanması" gibi algılanan bir '
        'duruma yol açabiliyordu. Aynı sorun points getter\'ında da vardı '
        '(her okumada tüm liste kopyalanıyordu). İkisi de artık O(1): '
        'mesafe her yeni nokta geldiğinde tek seferlik eklenerek '
        'tutuluyor, points ise kopyalamak yerine canlı bir görünüm '
        'döndürüyor. Kayıt süresi ne kadar uzarsa uzasın her güncelleme '
        'artık sabit hızda kalıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.50 beta',
    date: '2026-08-15',
    note:
        'Android\'de v1.4.49\'un açılışta bembeyaz ekranda kalma regresyonu '
        'düzeltildi. Kök sebep: karo isteğine User-Agent koymak için '
        'oluşturulan const header map\'i, flutter_map TileLayer\'ın '
        'Android\'de çağırdığı headers.putIfAbsent ile uyumsuzdu '
        '(unmodifiable map → UnsupportedError → release\'te boş beyaz '
        'ekran). Header map artık değiştirilebilir; Topo yine resmi '
        'OpenTopoMap.',
  ),
  ChangelogEntry(
    version: 'v1.4.49 beta',
    date: '2026-08-15',
    note:
        'Topo katmanındaki openmaps.fr "Limited Access" uyarısı giderildi. '
        'Sunucu, beğenmediği User-Agent isteklerine gerçek harita yerine '
        'politika uyarı görseli döndürüyordu. Topo yeniden resmi '
        'OpenTopoMap (tile.opentopomap.org) kaynağına alındı; karo '
        'istekleri RideAtlas (com.rideatlas.app) User-Agent ile gidiyor. '
        'v1.4.48\'deki tam-katman sıfırlamama düzeltmesi duruyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.48 beta',
    date: '2026-08-15',
    note:
        'Topo/harita "kare kare yanıp sönme" düzeltildi. Kök sebep: bir '
        'karo yüklenemeyince (OpenTopoMap hız limiti) tüm TileLayer\'ın '
        'sıfırlanması - her 2 saniyede bir bütün harita yeniden çekiliyor, '
        'başarılı/başarısız karolar karışık görünüyordu. Bu tam-katman '
        'retry kaldırıldı; yalnızca budanan hatalı karolar yeniden '
        'deneniyor. Stil değişince ValueKey ile önbellek temizleniyor. '
        'Renkli topo, OTM uyumlu openmaps.fr sunucusuna taşındı '
        '(maxNativeZoom 17).',
  ),
  ChangelogEntry(
    version: 'v1.4.47 beta',
    date: '2026-08-15',
    note:
        'Topo katmanı Esri World_Topo_Map\'ten OpenTopoMap\'e alındı: '
        'yükseklik renkleri (yeşil → sarı → kahverengi) ve konturlar '
        'yeniden belirgin. Soluk "sokak-topo" görünümü yerine renkli '
        'outdoor stil. Tile sunucusu bazen hız limiti koyarsa mevcut '
        'otomatik yeniden deneme gri kareleri dolduruyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.46 beta',
    date: '2026-08-15',
    note:
        'Uygulama ikonu yenilendi: kırmızı pin + harita ızgarası korunarak '
        'kıvrılan yolun altına motosiklet silüeti eklendi. Harita türü '
        'seçicide sıra Sokak / Uydu / Topo / Koyu / Sade olacak şekilde '
        'düzenlendi (etiket: Topo). Kayıt ekranındaki canlı haritaya da '
        'katman düğmesi eklendi - tercih diğer harita ekranlarıyla ortak '
        'saklanıyor. Android/iOS/web/masaüstü launcher ikonları yeni '
        'kaynaktan yeniden üretildi.',
  ),
  ChangelogEntry(
    version: 'v1.4.45 beta',
    date: '2026-08-14',
    note:
        'Kullanıcı, v1.4.44\'teki sıçrama filtresinin haritadaki büyük '
        'zıplamayı yine de temizlemediğini gösterdi ve gerçek rota '
        'dosyasını paylaştı. Dosyayı inceleyince kök sebep netleşti: '
        'sıçrama tek bir "anlık imkansız" hız değil, cihaz dururken GPS\'in '
        'yaklaşık bir dakika boyunca ~1.7km uzakta donup kalıp sonra '
        'gerçek konuma geri dönmesiydi - her tek adım kendi başına "sadece '
        'hızlı" (~140 km/s) görünüyordu, mevcut mutlak hız eşiğini '
        '(300 km/s) geçmiyordu. gpx_parser.dart\'a yeni bir '
        'findExcursionPointIndices dedektörü eklendi: rota aniden uzağa '
        'sıçrayıp birkaç ölçüm içinde neredeyse aynı noktaya geri '
        'dönüyorsa (gerçek bir sürüşün asla yapmayacağı bir şey), aradaki '
        'noktalar GPS aksaklığı sayılıp otomatik filtreye ve "Anormal '
        'noktaları düzenle" ekranına dahil ediliyor. Kullanıcının '
        'paylaştığı 36.628 noktalık gerçek dosya üzerinde doğrulandı: '
        'algoritma tam olarak bozuk 11 noktayı buluyor, başka hiçbir '
        'gerçek sürüş/duraklama anını yanlışlıkla işaretlemiyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.44 beta',
    date: '2026-08-14',
    note:
        'Kullanıcı, kayıtlı bir rotanın "Ortalama hız"ının başka bir GPX '
        'programındakiyle uyuşmadığını bildirdi. İnceleme RideAtlas\'ın '
        'kendi içinde de bir tutarsızlık ortaya çıkardı: Özet sekmesindeki '
        '"Aktif sürüş süresi" molaları >=10dk eşiğiyle hesaplarken, hemen '
        'yanındaki "Ortalama hız" 1km/s altındaki her segmenti ayrıca '
        'tamamen hesap dışı bırakan farklı bir yöntem kullanıyordu - iki '
        'rakam Mesafe/Süre ile çarpıldığında birbirini tutmuyordu. Artık '
        '"Ortalama hız" da "Aktif sürüş süresi" ile aynı süreyi kullanıyor. '
        'Aynı bildirimde, tek bir kötü GPS noktasından kaynaklanan '
        'haritadaki "sıçrama" da gündeme geldi - iki parçalı çözüm eklendi: '
        '(1) böyle noktalar artık harita ve istatistik hesaplarında otomatik '
        'olarak yok sayılıyor (dosya değişmiyor), (2) "Rotalar" listesindeki '
        '⋮ menüsüne "Anormal noktaları düzenle" eklendi - tespit edilen '
        'noktaları görüp istediklerinizi kalıcı olarak rotadan silebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.4.43 beta',
    date: '2026-08-14',
    note:
        'v1.4.42\'deki düzeltme (duraklamada düşük hassasiyetli konuma '
        'geçmeyi engellemek) yeterli değilmiş - kullanıcı gerçek bir '
        'sürüşte ekran görüntüsüyle yine "Otomatik duraklatıldı"nın hiç '
        'kapanmadığını, sadece elle duraklat/devam ettirince çalıştığını '
        'gösterdi. Kod içinde asıl sebep bulundu: '
        'RecordingLocationService.kt\'deki konum callback\'i duraklama '
        'sırasında gelen HER fix\'i "if (isPaused) return" ile en baştan '
        'yok sayıyordu - GPS\'in kendisi düzelse bile hiçbir konum '
        'Flutter tarafına ulaşmıyordu, o yüzden hızı kontrol edip '
        'duraklamayı kaldıran mantık hiç çalıştırılamıyordu. Elle '
        'duraklat/devam ettir çalışıyordu çünkü o buton konum beklemeden '
        'direkt durumu değiştiriyor. Düzeltildi: duraklama sırasında da '
        'her konum artık Flutter\'a iletiliyor (hız kontrolü için) - sadece '
        'kayıtlı rotaya eklenmiyor, o davranış değişmedi.',
  ),
  ChangelogEntry(
    version: 'v1.4.42 beta',
    date: '2026-08-14',
    note:
        'v1.4.38/v1.4.41\'deki pil tasarrufu değişikliğinde daha ciddi bir '
        'hata vardı: kullanıcı mola sonrası bazen "Otomatik duraklatıldı" '
        'yazısının hiç kapanmadığını, gerçekten takılı kaldığını bildirdi '
        '(geçen sürümde ele alınan birkaç saniyelik gecikmeden farklı). '
        'Kök sebep: duraklama sırasında GPS isteği düşük hassasiyetli '
        '(PRIORITY_BALANCED_POWER_ACCURACY) moddaydı - bu Android\'in GPS '
        'çipi yerine WiFi/baz istasyonu konumlamasına geçmesine izin '
        'veriyor, ve bu kaynaklar genelde hız bilgisi vermiyor (0 '
        'dönüyor). Gerçekten hareket etmeye başlasanız bile ölçülen hız '
        'sıfıra yakın kalıp 6km/s eşiğini hiç geçemiyor, duraklama asla '
        'kapanmıyordu. Duraklama sırasında GPS çipi devrede kalacak '
        'şekilde (PRIORITY_HIGH_ACCURACY, sadece yenileme aralığı seyrek) '
        'düzeltildi - pil tasarrufu yenileme aralığından geliyor zaten, '
        'artık gerçek hız her zaman ölçülüyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.41 beta',
    date: '2026-08-14',
    note:
        'v1.4.38\'deki pil tasarrufu değişikliğinin yan etkisi düzeltildi: '
        'duraklama sırasında GPS 8 saniyede bire kadar yavaşlıyordu, bu da '
        'tekrar harekete geçtiğinizde "Otomatik duraklatıldı" yazısının '
        '8 saniyeye kadar ekranda asılı kalmasına neden oluyordu - '
        'kullanıcı bir ekran görüntüsüyle bunu yakaladı. Duraklamadaki GPS '
        'yenileme aralığı 3 saniyeye düşürüldü (aktif haldeki 1sn\'nin '
        '3 katı - hâlâ ciddi pil tasarrufu sağlıyor) - harekete geçiş artık '
        'çok daha hızlı fark ediliyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.40 beta',
    date: '2026-08-14',
    note:
        'v1.4.39\'daki isim sorma diyaloğunda gerçek bir hata vardı: '
        'girilen isim doğru soruluyordu ama Android\'in paylaşım ekranına '
        'geçince dosya rastgele/anlamsız bir isimle (UUID benzeri) '
        'görünüyordu - XFile.fromData Android\'de verilen ismi paylaşım '
        'sayfasına taşımıyormuş. Artık dosya önce gerçek adıyla diske '
        'yazılıp öyle paylaşılıyor, paylaşım ekranında da doğru isim '
        'görünüyor. Web tarafı etkilenmedi, orada zaten doğru çalışıyordu.',
  ),
  ChangelogEntry(
    version: 'v1.4.39 beta',
    date: '2026-08-14',
    note:
        'Harita ekranındaki paylaş/dışa aktar akışı artık format '
        'sorusundan sonra dosya ismini de soruyor - varsayılan olarak '
        'rotanın kayıtlı ismi geliyor, isterseniz değiştirebilirsiniz. '
        'Özellikle birleştirilmiş rotalarda (otomatik "A + B" ismiyle '
        'gelenler) faydalı.',
  ),
  ChangelogEntry(
    version: 'v1.4.38 beta',
    date: '2026-08-14',
    note:
        'Pil tasarrufu: incelendiğinde ortaya çıktı ki oto-duraklama ve '
        'manuel duraklama sadece görsel/kayıt filtresiydi - GPS çipi '
        'arkada hâlâ tam hızda (1 saniyede bir, yüksek hassasiyet) çalışıp '
        'pil tüketmeye devam ediyordu. Artık duraklama başlar başlamaz '
        'native GPS isteği yavaşlıyor (8 saniyede bir, düşük güç modu); '
        'hareket algılanır algılanmaz eski hızına (1sn/yüksek hassasiyet) '
        'dönüyor. Hem otomatik hem elle duraklatma bu değişiklikten '
        'yararlanıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.37 beta',
    date: '2026-08-14',
    note:
        'Test sürümü: yerel Flutter + Android SDK derleme zinciri '
        'doğrulandı. Ürün davranışı v1.4.36 ile aynı; etiket yeni APK/web '
        'yayınının geldiğini doğrulamak için.',
  ),
  ChangelogEntry(
    version: 'v1.4.36 beta',
    date: '2026-08-13',
    note:
        'İki ekran görüntüsüyle yakalanan iki gerçek harita hatası '
        'düzeltildi: (1) Kırmızı rota çizgisinde ara sıra beliren keskin '
        '"sıçrama"lar (özellikle kavşak/yüksek bina yakınlarında) - GPS '
        'servisinden gelen fiziksel olarak imkansız hızlı sıçramalar artık '
        'rotaya hiç eklenmiyor, kaydedilen iz temiz kalıyor. (2) Harita '
        'yön-takip (course-up) modunun "neden yukarı gitmiyor" sorunu - '
        'kök neden bulundu: bilgi sayfasından haritaya her geçişte, harita '
        'widget\'ı yeniden kurulurken flutter_map kütüphanesinin kendi iç '
        'olayı ("boyut değişti") yanlışlıkla "kullanıcı haritayı elle '
        'kaydırdı" sanılıp yön-takip modunu sessizce kapatıyordu - siz hiç '
        'dokunmasanız bile. Artık sadece gerçek sürükleme/yakınlaştırma '
        'hareketleri modu kapatıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.35 beta',
    date: '2026-08-13',
    note:
        'Kayıt ekranının canlı bilgi sayfasındaki kartların varsayılan '
        'sırası değişti: Aktif sürüş süresi/Mesafe, Mola süresi/Son '
        'moladan bu yana, Ortalama hız/Maks. hız, Maks. irtifa/Min. '
        'irtifa, İniş/Tırmanış, en altta tek başına Yükseklik. Bu sadece '
        'varsayılan - kartları basılı tutup sürükleyerek istediğiniz gibi '
        'değiştirmeye devam edebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.4.34 beta',
    date: '2026-08-12',
    note:
        'Aktif sürüş süresi mantığı gözden geçirildi: artık her durduğunuzda '
        '(kısa duraklama da olsa) ekranda anında donuyor - önceden hiç '
        'donmuyordu, sadece 10dk+ molalar sonradan düşülüyordu. Tekrar '
        'harekete geçince: duraklama 10 dakikanın altındaysa o süre geriye '
        'dönük olarak aktif sürüşe eklenir (küçük bir sıçrama görürsünüz), '
        '10 dakika ve üzeriyse mola sayılır. Toplam süre = Aktif sürüş + '
        'Mola süresi eşitliği hep korunuyor. Ayrıca "Son moladan bu yana" '
        'sayacı, devam eden bir molayı (10dk+ duraklamayı) artık kendi '
        'içine katmıyor - mola sürerken sıfırda duruyor, mola bitip tekrar '
        'harekete geçince sıfırdan saymaya başlıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.33 beta',
    date: '2026-08-12',
    note:
        'Kayıt ekranının canlı bilgi sayfasındaki kartlar çok küçük '
        'kalıyordu, altta boş yer duruyordu - artık her satır kalan dikey '
        'alanı doldurup büyüyor, kartların içindeki yazı da kart boyutuna '
        'göre otomatik ölçekleniyor. Ayrıca artık Ayarlar\'a gitmeden, tam '
        'telefon ana ekranındaki uygulama ikonlarını taşıma gibi: bir '
        'kartı parmakla basılı tutup başka bir kartın üzerine sürükleyip '
        'bırakarak yerlerini doğrudan değiştirebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.4.32 beta',
    date: '2026-08-12',
    note:
        'Maks./Min. irtifa etiketleri taşıyordu ("Maksimum ..." gibi '
        'kesiliyordu) - kısaltıldı ve kart yazı boyutu küçültüldü. Kayıt '
        'ekranındaki "Toplam süre" yazısı kaldırıldı, sadece ikon+süre '
        'kaldı. Oto-duraklama artık 3 saniye durunca devreye giriyor '
        '(önceden 15 saniyeydi) - bu sadece görsel "bekleniyor" rozeti, '
        'mola sayımını (10 dakika eşiği) etkilemiyor. Ayarlar\'a yeni bir '
        'ekran eklendi: "Kayıt ekranı kartları" - kayıt ekranının canlı '
        'bilgi sayfasındaki kartları (sürüş süresi, mesafe, irtifa, hız '
        'vb.) sürükleyip istediğiniz sıraya koyabilir, istemediklerinizi '
        'anahtarla kapatabilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.4.31 beta',
    date: '2026-08-12',
    note:
        'Kayıt ekranı canlı bilgi sayfasında aktif sürüş süresi artık '
        'mesafenin hemen yanında (Günlük sekmesindeki süre+km eşleşmesiyle '
        'aynı mantık) - mola süresi de yükseklikle eşleşti. Harita '
        'sayfasındaki küçük hız kutusu belirgin şekilde büyütüldü.',
  ),
  ChangelogEntry(
    version: 'v1.4.30 beta',
    date: '2026-08-12',
    note:
        'KRİTİK CI düzeltmesi (3. adım): Gradle ve AGP\'den sonra bu sefer '
        'de Kotlin sürümü (2.1.20) Flutter\'ın yeni minimum gereksinimini '
        '(2.2.20) karşılamıyordu. Kotlin 2.2.20\'ye yükseltildi - hâlâ '
        'AGP 9\'un altında kalınıyor (file_picker gibi eklentilerin Kotlin '
        'derlemesini bozmaması için). Uygulama tarafında görünür bir '
        'değişiklik yok.',
  ),
  ChangelogEntry(
    version: 'v1.4.29 beta',
    date: '2026-08-12',
    note:
        'KRİTİK CI düzeltmesi (devam): bir önceki Gradle yükseltmesi tek '
        'başına yetmedi - Flutter bu sefer de Android Gradle Plugin '
        'sürümünün (8.11.0) en az 8.11.1 olmasını istedi. AGP 8.11.1\'e '
        'yükseltildi (hâlâ 9\'un altında - file_picker gibi bazı '
        'eklentilerin Kotlin derlemesini bozmaması için AGP 9+\'a '
        'geçilmiyor). Uygulama tarafında görünür bir değişiklik yok.',
  ),
  ChangelogEntry(
    version: 'v1.4.28 beta',
    date: '2026-08-12',
    note:
        'Kayıt ekranındaki en üstteki "Toplam süre" şeridi (ikon+etiket+'
        'rakam hepsi tek satırda) dengesiz duruyordu - artık ikon+etiket '
        'üstte, büyük süre rakamı hemen altında ortalanmış. Ayrıca: '
        'Günlük sekmesindeki gün ayrımının zaten takvim günü (gece yarısı) '
        'sınırına göre otomatik olduğu doğrulandı - ek bir değişiklik '
        'gerekmedi.',
  ),
  ChangelogEntry(
    version: 'v1.4.27 beta',
    date: '2026-08-12',
    note:
        'KRİTİK CI düzeltmesi: bir önceki push\'ta Android APK derlemesi '
        'başarısız oldu - CI\'daki Flutter "stable" kanalı kendiliğinden '
        'yeni bir sürüme geçmiş ve artık en az Gradle 8.14.0 istiyor, '
        'projeyse 8.13\'e sabitliydi. android/gradle/wrapper/'
        'gradle-wrapper.properties 8.14\'e yükseltildi. Uygulama '
        'tarafında görünür bir değişiklik yok.',
  ),
  ChangelogEntry(
    version: 'v1.4.26 beta',
    date: '2026-08-12',
    note:
        'Bir önceki sürümde "ikon rengi/büyüklüğü" ayarı yanlışlıkla '
        'sadece istatistik kartı ikonlarına eklenmişti - kullanıcı aslında '
        'harita üzerindeki araç ikonunu (motor/araba işaretçisi) '
        'kastetmişti. Araç ikonu seçim ekranı de aynı mantığa geçti: araç '
        'türü (klasik nokta/motosiklet/araba), renk ve büyüklük artık üç '
        'ayrı, birbirinden bağımsız seçim - önceden bunlar 10 sabit '
        'kombinasyondan biri olarak seçilebiliyordu (ör. "seçenek 3" hem '
        'belirli bir rengi hem belirli bir boyu birlikte getiriyordu), '
        'artık istediğin rengi istediğin boyla eşleştirebilirsin.',
  ),
  ChangelogEntry(
    version: 'v1.4.25 beta',
    date: '2026-08-12',
    note:
        'Analiz paneli ve kayıt bilgi sayfasında bir dizi düzen '
        'düzeltmesi: (1) Özet sekmesinin en üstteki 3\'lü şeridi '
        '("Mesafe/Aktif sürüş süresi/Maks. hız") uzun etiket yüzünden '
        'dengesiz görünüyordu - Maks. hız yerine Ortalama hız kondu, sürüş '
        'süresi sütununa daha fazla yer ayrıldı. (2) Aynı sekmenin Zaman '
        'grid\'inde: Ortalama hız\'ın yanına Maks. hız eklendi, Maksimum/'
        'Minimum irtifa satırı Tırmanış/İniş\'in üstüne taşındı, Pil kutusu '
        'grid\'den çıkarılıp ayrı, ortalanmış bir satır oldu. (3) Yükseklik '
        'sekmesinin en altına büyük punto ile "Son irtifa" eklendi. (4) '
        'Kayıt ekranının canlı bilgi sayfasında: Maksimum/Minimum irtifa '
        'yukarı, Tırmanış/İniş aşağı taşındı, Ortalama hız\'ın yanına '
        'Maks. hız geldi, Son moladan bu yana kendi satırına geçti. (5) '
        'Günlük sekmesinde sürüş süresi artık mesafeden önce (yan yana '
        'kalıyor). (6) Canlı harita üstündeki Süre/Mesafe/Yükseklik '
        'kutularının değerleri artık etiketlerinin yanında değil altında, '
        'ortalanmış.',
  ),
  ChangelogEntry(
    version: 'v1.4.24 beta',
    date: '2026-08-12',
    note:
        'v1.4.23\'te Analiz panelinin Özet sekmesine eklenen "Son moladan '
        'bu yana" kartı kaldırıldı - kaydedilmiş/içe aktarılmış bir rota '
        'için "şu ana kadar" gibi bir zaman kavramı anlamsız, bu ancak '
        'canlı, devam eden bir kayıt için mantıklı bir bilgi. Kayıt '
        'ekranının bilgi sayfasında (canlı) olduğu gibi duruyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.23 beta',
    date: '2026-08-12',
    note:
        'Kayıtlı/yüklenmiş rotalar için ayrı bir tam ekran "özet" sayfası '
        '(mavi kartlı) eklenmişti (v1.4.19), ama zaten var olan Analiz '
        'panelinin Özet sekmesiyle neredeyse aynı bilgileri gösteriyordu - '
        'aynı rota için iki ayrı özet ekranı olması kafa karıştırıcıydı. '
        'Ayrı mavi sayfa tamamen kaldırıldı; onda olup Analiz panelinde '
        'olmayan bilgiler (tırmanış, iniş, son moladan bu yana geçen süre) '
        'Analiz panelinin Özet sekmesine eklendi. Artık rota istatistikleri '
        'için tek bir yer var.',
  ),
  ChangelogEntry(
    version: 'v1.4.22 beta',
    date: '2026-08-12',
    note:
        'Özet sayfalarındaki (hem canlı kayıt hem kayıtlı rota) tırmanış/'
        'iniş/maksimum irtifa/minimum irtifa kartları tek satırda 4\'lü '
        'gösteriliyordu, çok sıkışık duruyordu. Artık iki satıra bölündü: '
        'tırmanış ve iniş bir satırda, maksimum ve minimum irtifa hemen '
        'altındaki satırda.',
  ),
  ChangelogEntry(
    version: 'v1.4.21 beta',
    date: '2026-08-12',
    note:
        'Bir seferde birçok küçük düzeltme: (1) Uygulama açılışında '
        'yarım kalmış kayıtları otomatik "kurtarıp" rota listesine ekleyen '
        'özellik kaldırıldı - anlık aksaklıklarda ortaya çıkan sahte '
        'kayıtlarla listeyi karıştırıyordu, artık böyle bir kalıntı '
        'sessizce siliniyor. (2) Mola tanımı değişti: artık sadece 10 '
        'dakika ve üzeri süren duruşlar "mola" sayılıyor - kısa bir kırmızı '
        'ışık/duraklama artık sürüş süresine dahil kalıyor, mola süresini '
        'şişirmiyor (hem canlı kayıtta hem kayıtlı rota özetinde). (3) '
        '"Ortalama hız" artık gerçekten sadece sürüş süresi üzerinden '
        '(mesafe ÷ hareket hâlindeki süre) hesaplanıyor. (4) Kayıt '
        'ekranındaki canlı haritanın üstündeki Süre/Mesafe/Yükseklik '
        'kutuları artık hız rakamının kendi satırında değil, altında ayrı '
        'bir satırda - hız 3 haneye çıkınca artık o kutuları sıkıştırıp '
        'okunmaz hâle getirmiyor. (5) Ayarlar\'a yeni bir "İstatistik ikon '
        'görünümü" eklendi: kart ikonlarının rengini ve büyüklüğünü '
        'istediğin gibi seçebiliyorsun. (6) Hem canlı kayıt hem kayıtlı '
        'rota özet sayfalarında: "Toplam süre" şeridi kaldırıldı (Sürüş '
        'süresi + Mola süresi zaten yeterli), "Maks. hız" kartının yanına '
        '"Son moladan bu yana" geçen süre eklendi, tırmanış/iniş/maksimum '
        'irtifa/minimum irtifa artık tek satırda yan yana - hepsi aynı '
        'irtifa profiline ait oldukları için birlikte okunuyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.20 beta',
    date: '2026-08-12',
    note:
        'GPS hız/yön gecikmesine farklı bir çözüm denendi: bir telefonun '
        'GPS çipi zaten gerçekçi olarak saniyede birden hızlı ölçüm '
        'üretemiyor (bir önceki sürümde aralık zaten bu tavana çekilmişti), '
        'yani aralığı daha da kısaltmanın faydası yok - asıl sorun her yeni '
        'ölçüm gelene kadar rakamın/haritanın olduğu yerde donup sonra bir '
        'anda zıplaması. Artık hız rakamı (hem kayıt hem bilgi sayfasında) '
        've harita kamerası (konum + yön birlikte) her yeni ölçümde hedefe '
        'doğru sürekli, akıcı bir animasyonla kayıyor - veri gerçekte hâlâ '
        '~1 saniyede bir gelse de ekran hiç durağan görünmüyor, sürekli '
        'canlı/hareket hâlinde hissettiriyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.19 beta',
    date: '2026-08-12',
    note:
        'Kayıtlı/yüklenmiş rotalar için de kayıt ekranının bilgi sayfasına '
        'benzer bir "özet" sayfası eklendi (harita ekranındaki yeni ikonla '
        'geçiliyor): en üstte büyük bir "Toplam süre" şeridi, altında '
        'sürüş süresi/mola süresi çifti, ardından mesafe, ortalama hız, '
        'maks. hız, tırmanış, iniş, maksimum irtifa ve minimum irtifa - '
        'hepsi aynı mavi kart tasarımıyla. Ayrıca kayıt ekranının bilgi '
        'sayfasındaki, küçük olduğu için okunması güç hız/yükseklik mini '
        'grafikleri kaldırıldı; yerlerine maksimum irtifa ve minimum '
        'irtifa kutuları eklendi.',
  ),
  ChangelogEntry(
    version: 'v1.4.18 beta',
    date: '2026-08-11',
    note:
        'KRİTİK düzeltme: hız göstergesi çok gecikmeli görünüyordu, harita '
        'da bazen gerçek yönle uyuşmayan bir tarafa dönmüş kalıyordu - asıl '
        'sebep, hem kayıt için kullanılan native GPS servisinin hem de '
        'haritayı döndüren konum akışının sadece 5 saniyede bir '
        'güncellenmesiydi (bir de native tarafta 2 saniyelik ek eşik '
        'vardı). İkisi de artık saniyede bir güncelleniyor (native '
        'tarafta ek eşik 0.5 saniyeye indirildi) - normal bir navigasyon '
        'uygulamasının güncelleme hızına yakın. Hız artık gerçek '
        'hızlanma/yavaşlamayı çok daha yakından takip ediyor, harita da '
        'dönüşleri çok daha hızlı yakalıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.17 beta',
    date: '2026-08-11',
    note:
        'Kayıt bilgi sayfasında "Toplam süre" şeridi en az 2 kat '
        'büyütüldü - artık alttaki mavi kartların yazılarından belirgin '
        'şekilde daha büyük. Rotalar listesinde: ayarlar ikonu artık çoklu '
        'seçim modunda da görünüyor (önceden kayboluyordu); seçim '
        'araç çubuğuna "Tümünü göster" onay kutusu eklendi (işaretlenince '
        'tüm rotalar tek seferde seçilir); "Haritada göster"in yanına bir '
        'sil ikonu eklendi, seçili rotaları tek dokunuşla (onay '
        'istenerek) siler.',
  ),
  ChangelogEntry(
    version: 'v1.4.16 beta',
    date: '2026-08-11',
    note:
        'Bilgi sayfası yeniden düzenlendi: "Toplam süre" artık en üstte, '
        '"Otomatik duraklatıldı" bandının üzerinde kendi şeridinde; süre '
        'kutuları satırında toplam süre yerine artık mola süresi var '
        '(aktif sürüş süresinin yanında); "Yükseklik" kartı istatistik '
        'ızgarasında artık "Mesafe"nin hemen yanında; mavi kartlardaki '
        'ikon+yazı bloğu artık kutunun ortasında (önceden sola yaslıydı); '
        'hız/yükseklik grafiklerine ayrılan alan büyütüldü (mola süresi '
        've toplam süre ızgaradan çıkınca boşta kalan yer değerlendirildi). '
        'Harita sayfasında hız kutusuna biraz daha nefes alanı bırakmak '
        'için sağdaki süre/mesafe/yükseklik kutusunun yazıları azıcık '
        'küçültüldü (yine de eski halinden büyük).',
  ),
  ChangelogEntry(
    version: 'v1.4.15 beta',
    date: '2026-08-11',
    note:
        'KRİTİK düzeltme: haritadaki araç işaretçisi hâlâ yukarı bakmıyordu '
        '- gerçek sebep, flutter_map\'in Marker bileşeninin varsayılan '
        'olarak haritayla BİRLİKTE dönmesiydi (rotate:true set edilmemişti), '
        'yani harita yön-takip için döndükçe işaretçi de onunla birlikte '
        'dönüp ekranda yanlış açıda kalıyordu. Artık işaretçi haritanın '
        'dönüşüne karşı sabitlenip her zaman yukarı bakıyor. Ayrıca: harita '
        'sayfasındaki hız/süre/mesafe/yükseklik kutularının yazıları en az '
        '2 kat büyütüldü; bilgi sayfasındaki alt kartların değerleri artık '
        'aktif sürüş süresi kutusuyla aynı büyüklükte (gerekirse sayfa '
        'kayabilir); bilgi sayfasının rengi kırmızı ağırlıklı temadan mavi-'
        'beyaz ağırlıklı bir palete çevrildi; hız grafiğindeki sürüşün '
        'başındaki anlamsız boş bölge kaldırıldı, grafik artık gerçek '
        'hareketin başladığı noktadan başlıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.14 beta',
    date: '2026-08-11',
    note:
        'Bilgi sayfası baştan tasarlandı: hız rakamı çok daha büyük ve '
        'farklı (italik, kalın, parlamalı) bir fontla gösteriliyor; arka '
        'plan artık düz renk yerine hafif hareketli, modern bir gradyan+'
        'parlama efekti; önceki 7 farklı renkli kart tek bir tutarlı renge '
        '(cam görünümlü, kenarlıklı) çevrildi. Hız ve yükseklik '
        'grafiklerinde artık en yüksek (ve yükseklikte en düşük) noktalar '
        'her zaman bir nokta+etiketle sabit olarak işaretli, grafiğin ekseni '
        'zamanla yeniden ölçeklense bile pik değer görünür kalıyor. '
        'Haritaya geçiş düğmesi sol '
        'alttan sağ üste taşındı - artık iki sayfada da aynı köşede.',
  ),
  ChangelogEntry(
    version: 'v1.4.13 beta',
    date: '2026-08-11',
    note:
        'Harita sayfasının üst bilgi çubuğu istenen şablona göre '
        'düzenlendi: solda tek büyük hız kutusu, sağda süre/mesafe/'
        'yükseklik artık yan yana üç sütun değil, alt alta üç satır.',
  ),
  ChangelogEntry(
    version: 'v1.4.12 beta',
    date: '2026-08-11',
    note:
        'Düzeltme: v1.4.9\'da titremeyi gidermek için eklenen "son birkaç '
        'okumanın ortalaması" yöntemi, GPS güncellemeleri seyrek geldiğinde '
        '(~5 saniyede bir) dönemeçlerde haritanın gerçek yöne yetişmesini '
        'yavaşlatıyordu - yol dönüyor ama harita hâlâ eski yöne bakıyor gibi '
        'görünüyordu. Ortalama alma yerine artık hız filtresiyle aynı '
        'mantık kullanılıyor: gerçek bir dönüş (ne kadar keskin olursa '
        'olsun) anında uygulanıyor, sadece fiziksel olarak imkansız ani '
        'sıçramalar (tek bir kötü GPS ölçümü) göz ardı ediliyor. Ayrıca '
        'bilgi panelinden haritaya geçerken harita artık bir sonraki GPS '
        'güncellemesini beklemeden anında doğru konum/yöne senkronize '
        'ediliyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.11 beta',
    date: '2026-08-11',
    note:
        'Düzeltme: GPS ara sıra tek bir kötü ölçümle fiziksel olarak '
        'imkansız bir hız sıçraması veriyordu (ör. 95 km/s seyirde aniden '
        '200 km/s görünüp hemen eski hıza dönmesi) - hız grafiğinde ve '
        'maks. hız istatistiğinde belirgin dikenler olarak görünüyordu. '
        'Artık son kabul edilen okumaya göre saniyede ~30 km/s\'i aşan '
        'imkansız hızlanma/yavaşlamalar (gerçek bir motorun '
        'yapamayacağı kadar ani) hem canlı hız göstergesinde hem de hız '
        'grafiği/istatistik hesaplamalarında göz ardı ediliyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.10 beta',
    date: '2026-08-11',
    note:
        'Bilgi paneli geri bildirimlere göre yeniden düzenlendi: '
        'en üstte artık büyük puntoyla anlık hız var, hemen altında aktif '
        'sürüş süresi ve toplam süre yan yana; onların altında renkli, '
        'daha kompakt bir istatistik ızgarası (mesafe, mola, ort./maks. '
        'hız, yükseklik, çıkış/iniş); en altta da hız ve yükseklik '
        'grafikleri yan yana - hepsi kaydırma olmadan tek ekrana sığıyor. '
        'Harita düğmesi sağ üstten sol alta taşındı.',
  ),
  ChangelogEntry(
    version: 'v1.4.9 beta',
    date: '2026-08-11',
    note:
        'Kayıt ekranı iki sayfaya ayrıldı: kayıt başlar başlamaz artık '
        'önce toplam süre, aktif sürüş süresi, mola süresi, ortalama/maks. '
        'hız, toplam çıkış/iniş ve hız/yükseklik grafiklerinin olduğu bir '
        'bilgi paneli açılıyor; sağ üstteki düğmeyle haritaya geçilebiliyor. '
        'Ayrıca haritanın yön-yukarı dönüşü artık sağa sola titremiyor - '
        'son birkaç GPS yönünün ortalaması alınıp yumuşak şekilde '
        'döndürülüyor (navigasyon uygulamaları gibi).',
  ),
  ChangelogEntry(
    version: 'v1.4.8 beta',
    date: '2026-08-11',
    note:
        'v1.4.7\'nin devamı: bazı telefonlarda (özellikle MIUI gibi '
        'agresif arka plan yönetimi olanlarda) sistem, öldürdüğü kayıt '
        'servisini hiç yeniden başlatmıyor - START_STICKY yeniden '
        'başlatması hiç tetiklenmiyor, dolayısıyla önceki düzeltmenin '
        'kurtarma kodu da hiç çalışmıyordu. Veri dosyası diskte kalıyordu '
        'ama kimse onu geri okumuyordu. Artık uygulama her açılışta '
        'yarım kalmış bir kayıt olup olmadığını kontrol ediyor; varsa '
        'otomatik olarak rota listesine kaydediyor ve bildirim gösteriyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.7 beta',
    date: '2026-08-11',
    note:
        'KRİTİK düzeltme: çok düşük pilde (veya OEM\'in agresif pil '
        'yönetiminde) Android tüm uygulamayı öldürüp arka plandaki kayıt '
        'servisini kendi kendine yeniden başlattığında, kod bunu "yeni bir '
        'kayıt başlıyor" sanıp o ana kadar diskte biriken GPS verisini '
        'siliyordu - kayıt "durmuş" gibi görünüyor, veri de gidiyordu. '
        'Artık sistemin kendi yeniden başlatması ile gerçek bir yeni kayıt '
        'ayırt ediliyor; önceki veri silinmek yerine geri yükleniyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.6 beta',
    date: '2026-08-10',
    note:
        'Yeni: Android Auto\'da kayıt ekranı artık gerçek bir harita '
        'gösteriyor - telefondaki gibi yön-yukarı (course-up) dönen, '
        'kat edilen rota çizgisiyle. Karolar telefonun zaten kullandığı '
        'ücretsiz Carto kaynağından (API anahtarı gerekmiyor). Deneysel: '
        'gerçek bir araçta test edilemedi, sorun görürseniz bildirin.',
  ),
  ChangelogEntry(
    version: 'v1.4.5 beta',
    date: '2026-08-10',
    note:
        'Düzeltme: Android Auto uygulama listesinde RideAtlas hiç '
        'görünmüyordu. Sebebi, androidx.car.app kütüphanesinin zorunlu '
        'tuttuğu bir manifest ayarının (minCarApiLevel) eksik olmasıydı - '
        'bu olmadan Android Auto uygulamayı hatasız şekilde sessizce '
        'listeden düşürüyor. Eklendi.',
  ),
  ChangelogEntry(
    version: 'v1.4.4 beta',
    date: '2026-08-09',
    note:
        'Düzeltme: bir önceki sürümde "Aktif sürüş süresi" nokta-nokta '
        'hıza bakarak hesaplanmaya başlamıştı, ama bu Günlük sekmesindeki '
        '"Sürüş süresi"nin kullandığı (20+ dk duraklama kümeleri tespit '
        'eden) yöntemden farklıydı - aynı rota için iki sekmede farklı '
        'sayılar görünebiliyordu. Artık Özet sekmesi de Günlük sekmesiyle '
        'aynı mola tespitini kullanıyor; "Aktif sürüş süresi" ve "Mola '
        'süresi" artık her iki sekmede de tutarlı.',
  ),
  ChangelogEntry(
    version: 'v1.4.3 beta',
    date: '2026-08-09',
    note:
        'Önemli düzeltme: Analiz > Özet sekmesinde "Aktif sürüş süresi" '
        'bazı rotalarda "Toplam süre" ile birebir aynı çıkıyor, bu yüzden '
        '"Mola süresi" de her zaman 0 görünüyordu. Kök neden: eski hesap, '
        'sadece noktalar arasında 60 saniyeden uzun bir boşluk varsa "mola '
        'verildi" sayıyordu - ama birçok GPS cihazı/uygulaması dururken de '
        'sabit aralıklarla nokta kaydetmeye devam ediyor, bu da hiç boşluk '
        'oluşmamasına yol açıyordu. Artık her nokta çifti arasındaki gerçek '
        'hıza bakılıyor (duraklarda hız ~0 km/s), bu yüzden hangi cihazla '
        'kaydedilmiş olursa olsun doğru sonuç veriyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.2 beta',
    date: '2026-08-09',
    note:
        'Rota listesinde birden fazla rota seçtiğinizde artık "Birleştir" '
        'seçeneği de var - örneğin birkaç günlük bir gezinin her günü ayrı '
        'kaydedildiyse, seçilenler kendi ilk GPS zaman damgasına göre '
        'otomatik sıralanıp (seçim sırası önemli değil) tek bir yeni rotada '
        'birleştiriliyor; yeni rota için bir isim soruluyor. Orijinal '
        'rotalar silinmiyor, sadece isimlerine "(birleştirildi)" ekleniyor; '
        'üzerlerindeki fotoğraf/videolar da yeni rotaya kopyalanıyor.',
  ),
  ChangelogEntry(
    version: 'v1.4.1 beta',
    date: '2026-08-09',
    note:
        'Analiz > Özet sekmesi sadeleştirildi: Tırmanış çıkarıldı (zaten '
        'Yükseklik sekmesinde var); yerine Ortalama hız, Minimum/Maksimum/'
        'Son irtifa ve Mola süresi (toplam süre − aktif sürüş süresi) '
        'eklendi. "Net süre" etiketi "Aktif sürüş süresi" oldu. Üstteki üç '
        'büyük değerin (mesafe, süre, hız) uzun metinlerde ortadan '
        'bölünmesine yol açan görünüm hatası düzeltildi.',
  ),
  ChangelogEntry(
    version: 'v1.4.0 beta',
    date: '2026-08-09',
    note:
        'Sürüş sırasında çekilen fotoğraflar rotaya bağlanabiliyor: kayıt '
        'bitirilip kaydedildiğinde, o sürüş süresince telefonun galerisine '
        'eklenmiş fotoğraf/videolar varsa bunlar listelenir, hangilerinin '
        'rotaya ekleneceğini seçebilirsiniz. Konumu bilinmeyen bir foto/'
        'video seçilirse, haritadan elle nereye ait olduğunu işaretlemeniz '
        'istenir. Rota haritasına, fotoğraf/video konumlarını gösterme veya '
        'gizleme için yeni bir düğme eklendi (varsayılan: gösteriliyor); '
        'gösterildiğinde her biri haritada küçük bir önizlemeyle işaretlenir '
        've dokununca tam ekran açılır. Fotoğraf/video daha sonra da elle '
        'eklenebilir - bu zaten var olan özellik değişmedi.',
  ),
  ChangelogEntry(
    version: 'v1.3.48 beta',
    date: '2026-08-09',
    note:
        'Kayıt ekranındaki harita artık her zaman yön-takip (course-up) '
        'modunda - kuzey-sabit moda geçiş kaldırıldı, konum tuşu artık her '
        'basışta sadece ortalıyor. Üstteki süre/mesafe/yükseklik kutusu '
        'yeniden düzenlendi: değerler dar ekranlarda birbirine karışıp '
        'taşmak yerine, aralarında ince bir ayraçla, kendi sütunlarında '
        'okunaklı şekilde gösteriliyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.47 beta',
    date: '2026-08-09',
    note:
        'Ekran kapalı / uyku modunda GPS kaydının kesilmesine kök çözüm: '
        'konum artık Flutter/geolocator akışı yerine Android native '
        'foreground serviste toplanıyor (Fused Location + wake lock + kalıcı '
        'bildirim). Flutter motoru Doze ile donsa bile noktalar native '
        'tampona yazılıyor; kayıt bitince rota bundan üretiliyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.46 beta',
    date: '2026-08-09',
    note:
        'Arka planda / ekran kilitliyken GPS kaydının kesilmesi için önemli '
        'düzeltme: eski LocationManager yolu modern Android\'de ekran '
        'kapanınca ~60 sn içinde GPS\'i durdurabiliyordu; kayıt artık Fused '
        'Location + kalıcı bildirim + 5 sn aralıklı güncelleme kullanıyor. '
        '"Her zaman izin ver" yoksa kayıt başlamıyor (Ayarlar\'a yönlendirir); '
        'pil muafiyeti de kayıttan önce isteniyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.45 beta',
    date: '2026-08-08',
    note:
        'Kayıt ekranındaki harita artık normal navigasyon uygulamaları gibi '
        'varsayılan olarak yön-takip (course-up) modunda açılıyor - harita, '
        'gidilen yöne göre dönüyor. Konum tuşuna basarak kuzey-sabit moda '
        'geçilebiliyor; hangi mod seçiliyse bir sonraki kayıtta da o '
        'hatırlanıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.44 beta',
    date: '2026-08-05',
    note:
        'Ekran kilitliyken GPS kaydının kesilmesi sorununun gerçek kök '
        'nedeni bulundu: uygulama Android\'den hiçbir zaman "her zaman" '
        '(arka planda) konum izni istemiyordu - bu yüzden telefonun Ayarlar '
        'ekranında bu seçenek hiç görünmüyordu, sadece "uygulama '
        'kullanılırken" seçilebiliyordu, pil izni/otomatik başlatma ne '
        'kadar açık olursa olsun bu durumda ekran kilitlenince konum '
        'kesiliyordu. Artık bu izin de isteniyor; kayıt başladığında hâlâ '
        'sadece "kullanılırken" izni varsa, Ayarlar\'ı açmanız için bir '
        'uyarı çıkıyor. Ayarlar ekranına da "Konum: Her zaman izin ver" '
        'kısayolu eklendi.',
  ),
  ChangelogEntry(
    version: 'v1.3.43 beta',
    date: '2026-08-05',
    note:
        'Ekran kilitliyken GPS kaydının kesilmesi sorunu için ek bir '
        'düzeltme: pil optimizasyonu muafiyeti ve otomatik başlatma izni '
        'verilmesine rağmen bazı telefonlarda (Xiaomi/MIUI doğrulandı) '
        'kayıt sırasında konum güncellemeleri hâlâ duruyordu - rota '
        'haritada düz bir çizgiyle "atlıyordu". Konum artık Google Play '
        'Servisleri\'nin FusedLocationProviderClient\'ı yerine Android\'in '
        'kendi GPS sağlayıcısı (LocationManager) üzerinden alınıyor; '
        'üretici pil yöneticileri genellikle Play Servisleri konumunu çok '
        'daha agresif kısıtlıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.42 beta',
    date: '2026-08-05',
    note:
        'Önemli düzeltme: bazı telefonlarda araç ikonunun rengi tüm '
        'ekranı kaplıyordu (harita ve Araç ikonu seçim ekranı dahil) - '
        'çalışma zamanında renklendirme yerine, her renk seçeneği artık '
        'önceden hazırlanmış ayrı bir görsel olarak geliyor, sorun '
        'kökten çözüldü. Uydu sayısı göstergesi artık bağlantı yeterliyken '
        '(4+ uydu) yeşil, azken kırmızı renkte gösteriliyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.41 beta',
    date: '2026-08-05',
    note:
        'Araç ve motor haritada artık emoji yerine gerçek, üstten çekilmiş '
        'araç fotoğraflarıyla gösteriliyor - her ikisi için de 5 renk ve '
        '5 ölçek seçeneği var (Ayarlar > Araç ikonu). Ana ekrandaki kayıt '
        'tuşunun altında ve kayıt ekranında, bağlı GPS uydu sayısını '
        'gösteren küçük bir rozet eklendi; Ayarlar > "Uydu sayısını göster" '
        'ile istenirse kapatılabilir.',
  ),
  ChangelogEntry(
    version: 'v1.3.40 beta',
    date: '2026-08-05',
    note:
        'Önemli düzeltme: bazı telefon üreticilerinin (Xiaomi/MIUI, '
        'Oppo/ColorOS, Samsung/OneUI gibi) ek pil kısıtlamaları yüzünden, '
        'ekran kapanınca kayıt sırasında GPS güncellemeleri duruyordu - bu '
        'foreground servis dışında, üretici bazlı ek bir kısıtlama. Artık '
        'kayıt başlarken uygulamayı pil optimizasyonundan muaf tutmanız '
        'için sistem izni isteniyor; Ayarlar > "Arka planda GPS izni" ile '
        'istediğiniz zaman tekrar açabilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.39 beta',
    date: '2026-08-05',
    note:
        'Oto-duraklama hassasiyeti düzeltildi: artık tekil GPS sıçramaları '
        'yerine son birkaç okumanın ortalamasına göre karar veriyor, '
        'durma/kalkma eşikleri de ayrı tutuldu (titreme olmasın diye). '
        'Araç ve motor işaretçileri renkli rozetli, gerçek emoji '
        'görsellerine geçti. Kayıt ekranındaki konum işaretçisine, '
        'MotionX-GPS\'teki gibi GPS yönünü gösteren yarı saydam bir '
        '"yön konisi" eklendi - kuzey-sabit moddayken de yön artık '
        'görülebiliyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.38 beta',
    date: '2026-08-05',
    note:
        'Ana ekrandaki kayıt düğmesi küçültüldü. Altında GPS durumu kısa '
        'süre görünüyor: GPS yoksa offline kayıt uyarısı, GPS gelince '
        'doğruluk bilgisiyle birlikte "hazır" mesajı (birkaç saniye sonra '
        'kaybolur, tıklanamaz).',
  ),
  ChangelogEntry(
    version: 'v1.3.37 beta',
    date: '2026-08-04',
    note:
        'Önemli düzeltme: v1.3.34\'te Android Auto eklenirken '
        'MainActivity\'nin Flutter motorunu ele alış şekli değişmişti, bu '
        'da Android\'de arka planda (uygulama küçültülünce) konum '
        'alınmasını bozmuştu - geri alındı, arka plan takibi eskisi gibi '
        'çalışıyor. Kayıt ekranındaki araç ikonu artık her zaman yukarı '
        'bakıyor; kuzey-sabit moddayken de artık kendi etrafında '
        'dönmüyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.36 beta',
    date: '2026-08-04',
    note:
        'REC göstergesi artık bağımsız bir kutu olarak ekranın üstünde '
        'yüzmüyor - ayarlar ikonunun hemen sağında, üst çubuktaki diğer '
        'ikonlarla aynı satırda, küçük yanıp sönen bir ikon olarak '
        'duruyor (önceden ayarlar ikonunun üstüne biniyordu). Rota '
        'haritasının üst çubuğundaki foto ekleme ikonu kaldırıldı - '
        'ekranın altındaki foto/video şeridinde zaten aynı işi yapan bir '
        'düğme var.',
  ),
  ChangelogEntry(
    version: 'v1.3.35 beta',
    date: '2026-08-04',
    note:
        'Kayıt ekranındaki konum tuşu artık gerçek bir mod anahtarı: zaten '
        'ortalanmışken her basış kuzey-sabit (harita hiç dönmez, araç '
        'ikonu gittiği yönü gösterecek şekilde döner) ile yön-takip '
        '(harita gittiğiniz yöne döner, araç ikonu hep yukarı bakar) '
        'arasında geçiş yapıyor. REC göstergesi artık ekranın hemen '
        'köşesinde, tüm kutusuyla yanıp sönerek duruyor - fark edilmesi '
        'daha kolay.',
  ),
  ChangelogEntry(
    version: 'v1.3.34 beta',
    date: '2026-08-04',
    note:
        'Android Auto desteği eklendi: telefonda başlatılan bir kayıt, '
        'arabanın ekranından da görülüp kontrol edilebiliyor - hız, süre, '
        'mesafe orada da gösteriliyor; duraklat/devam et ve bitir '
        'düğmeleri çalışıyor (sürüş güvenliği kuralları gereği araba '
        'ekranından isim yazılamıyor, kayıt otomatik bir isimle '
        'kaydediliyor). Telefon uygulamasının en az bir kez açılmış olması '
        'yeterli. CarPlay için Apple\'dan özel izin (entitlement) '
        'gerekiyor, henüz eklenmedi.',
  ),
  ChangelogEntry(
    version: 'v1.3.33 beta',
    date: '2026-08-04',
    note:
        'Önemli düzeltme: v1.3.32\'de kayıt ekranındaki hız/süre/mesafe/'
        'yükseklik kutusu bir düzen hatası yüzünden hiç görünmüyordu - '
        'düzeltildi. REC göstergesi sağ üst köşeye taşındı, artık kırmızı '
        'yanıp sönüyor ve "REC" yazısı içeriyor. Kayıt sürerken ana '
        'ekrandaki büyük "kayıt yap" düğmesi artık gizleniyor - geri dönmek '
        'için REC göstergesine dokunun.',
  ),
  ChangelogEntry(
    version: 'v1.3.32 beta',
    date: '2026-08-04',
    note:
        'Kayıt ekranı yenilendi: hız büyük punto ile öne çıkarıldı, süre/'
        'mesafe/yükseklik yanında küçük gösteriliyor, oto-duraklama rozeti '
        'büyütüldü. Geri tuşu artık kaydı durdurmuyor - kayıt arka planda '
        'sürerken ekran kenarında bir REC düğmesi beliriyor, dokununca '
        'kayıt ekranına dönülüyor. Kayıt başlarken araç ekranın ortasında '
        'başlıyor; konum tuşuna 2. kez basınca harita kuzeye dönüyor. Rota '
        'özetine net sürüş süresi, toplam süre ve pil başlangıç/bitiş '
        'yüzdesi eklendi. Ayarlar > Araç ikonu ile haritadaki "buradayım" '
        'işaretini motosiklet veya araba simgesiyle (5\'er ölçek/renk '
        'seçeneği) değiştirebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.31 beta',
    date: '2026-08-04',
    note:
        'Dil ikonu yerine Ayarlar ikonu geldi; içine Dil, Yardım (tüm '
        'özelliklerin detaylı anlatımı) ve Hakkında (güncel sürüm + sürüm '
        'geçmişi) bölümleri eklendi. Ekranda dolaşan versiyon rozeti '
        'kaldırıldı.',
  ),
  ChangelogEntry(
    version: 'v1.3.30 beta',
    date: '2026-08-03',
    note:
        'Versiyon etiketi artık ekranın sol kenarının ortasında - '
        'fotoğraf/video şeridiyle sol alt köşede üst üste binmiyordu.',
  ),
  ChangelogEntry(
    version: 'v1.3.29 beta',
    date: '2026-08-03',
    note:
        'Rota isminin altında artık ayın ve yılın (gün olmadan) yazdığı '
        'bir tarih gösteriliyor. Dosya adından gelen rota isimlerinin '
        'sonundaki gereksiz alt çizgi/tire gibi karakterler artık '
        'otomatik temizleniyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.28 beta',
    date: '2026-08-03',
    note:
        'Fotoğraf/video ekleme artık tek noktadan (galeriden ikisi '
        'birden seçilebiliyor). Rota adı artık üst çubuğun altında tam '
        'genişlikte, kesilmeden gözüküyor. Mola ve geceleme işaretleri '
        'artık rota ilk açıldığında gizli - istenirse düğmeyle '
        'açılıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.27 beta',
    date: '2026-08-02',
    note:
        'Rotalara artık video da eklenebiliyor (kameradan veya '
        'galeriden). Fotoğraf veya videoda konum bilgisi bulunamazsa, '
        'haritada nereye ait olduğunu elle işaretleyebiliyorsunuz.',
  ),
  ChangelogEntry(
    version: 'v1.3.26 beta',
    date: '2026-08-02',
    note:
        'İki düzeltme: kayda başlarken harita artık yanlış bir konuma '
        'zıplamıyor; ve "Güncelle" düğmesi artık APK\'yı indirip '
        'doğrudan kurulum ekranını açıyor (önceden sadece indiriyordu, '
        'kurmak için ayrıca dosyayı bulup açmak gerekiyordu).',
  ),
  ChangelogEntry(
    version: 'v1.3.25 beta',
    date: '2026-08-02',
    note:
        'Kayıt ekranında haritayı elle başka bir yere sürüklediğinizde '
        'artık konumunuza geri dönmek için bir düğme çıkıyor - önceden '
        'harita her GPS güncellemesinde otomatik olarak eski yerine '
        'dönüyordu.',
  ),
  ChangelogEntry(
    version: 'v1.3.24 beta',
    date: '2026-08-02',
    note:
        'Kayıt ekranı artık açılır açılmaz mevcut konumunuzu gösteriyor - '
        'önceden kayıt başlayana kadar (ve ilk GPS noktası gelene kadar) '
        'sabit bir varsayılan konumda kalıyordu.',
  ),
  ChangelogEntry(
    version: 'v1.3.23 beta',
    date: '2026-08-02',
    note:
        'Android uygulaması artık açılışta yeni bir sürüm olup olmadığını '
        'GitHub\'dan sessizce kontrol ediyor; varsa haritanın üstünde bir '
        '"Güncelle" düğmesi çıkıyor ve tek dokunuşla indirme sayfasını '
        'açıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.22 beta',
    date: '2026-08-02',
    note:
        'Android uygulamasında kayıt ekranındaki "sadece ön planda sürer" '
        'uyarısı artık yanlıştı - Android\'de arka planda da kaydettiğini '
        'doğru şekilde belirtiyor (web sürümünde uyarı hâlâ geçerli).',
  ),
  ChangelogEntry(
    version: 'v1.3.21 beta',
    date: '2026-08-02',
    note:
        'Rota haritasına fotoğraf ekleyebilme özelliği geldi: kameradan '
        'çekip veya galeriden seçip ekleyebilirsiniz. Konum bilgisi olan '
        'fotoğraflar haritada da küçük bir işaret olarak gösteriliyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.20 beta',
    date: '2026-08-02',
    note:
        'Android tarafında kayıt artık arka planda (uygulama küçültülse '
        'bile) bir bildirimle birlikte devam edebiliyor. Web tarafı '
        'değişmedi - hâlâ sekme ön plandayken kaydediyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.19 beta',
    date: '2026-08-02',
    note:
        'Rota haritasına geri dönüş oku eklendi (eksikti) ve rota '
        'listesinden bir rotaya girmek artık geçmişte liste ekranını '
        'bırakmıyor - böylece geri dönmek tek dokunuşla ana ekrana '
        'ulaşıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.18 beta',
    date: '2026-07-30',
    note:
        'Ana ekrana büyük bir kayıt düğmesi eklendi. Kayıt sırasında artık '
        'hız ve yükseklik de üstte gösteriliyor; uzun süre dursanız kayıt '
        'otomatik olarak duraklıyor, hareket edince kendiliğinden devam '
        'ediyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.17 beta',
    date: '2026-07-30',
    note:
        'Açılış haritası artık konumunuz bulunduğunda yakın plana zum '
        'yapmıyor; geniş, bölgesel bir görünümde kalıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.16 beta',
    date: '2026-07-30',
    note:
        'Uygulama artık, konumunuzu gösteren canlı bir haritayla açılıyor. '
        'Kaydettiğiniz rotalara sol üstteki liste ikonundan ulaşabilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.15 beta',
    date: '2026-07-28',
    note:
        'Rota listesindeki kırmızı kayıt düğmesiyle artık GPS ile canlı '
        'rota kaydı yapabilirsiniz. Not: bu, sadece sekme ön planda ve '
        'ekran açıkken çalışır - arka planda devam etmez.',
  ),
  ChangelogEntry(
    version: 'v1.3.14 beta',
    date: '2026-07-28',
    note:
        'Birden fazla rotayı aynı haritada gösterirken de, haritayı '
        'döndürdüğünüzde artık kuzeye dön pusulası çıkıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.13 beta',
    date: '2026-07-28',
    note:
        'Harita ekranındaki "Rotalar" penceresine de çoklu seçim eklendi: '
        'oradan da birden fazla rotayı işaretleyip aynı haritada '
        'gösterebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.12 beta',
    date: '2026-07-28',
    note:
        'Üst çubuktaki çoklu seçim ikonu, sadece 2+ rota varken değil, tek '
        'rota varken de artık görünüyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.11 beta',
    date: '2026-07-27',
    note:
        'Rota listesinde artık çoklu seçim var (üst çubuktaki seçim ikonu): '
        'birden fazla rotayı işaretleyip "Haritada göster" ile hepsini aynı '
        'haritada, farklı renklerle üst üste görebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.10 beta',
    date: '2026-07-27',
    note:
        'Topografik harita katmanı artık Esri altyapısından geliyor - '
        'OpenTopoMap bazen bazı kareleri (gri kutular) hiç yüklemiyordu.',
  ),
  ChangelogEntry(
    version: 'v1.3.9 beta',
    date: '2026-07-27',
    note:
        'Sol alttaki versiyon yazısına dokununca artık tüm sürüm geçmişini '
        '(hangi tarihte ne eklendiğini) gösteren bir liste açılıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.8 beta',
    date: '2026-07-27',
    note:
        'Geceleme noktaları artık gün değişiminin olduğu yere göre '
        'işaretleniyor, süre eşiğine göre değil - bu sayede hiçbir geceleme '
        'atlanmıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.7 beta',
    date: '2026-07-27',
    note:
        'Haritada artık gecelemeler (4 saat+ süren duraklar) molalardan '
        'farklı bir renk ve ikonla gösteriliyor - aynı göster/gizle '
        'düğmesiyle.',
  ),
  ChangelogEntry(
    version: 'v1.3.6 beta',
    date: '2026-07-27',
    note:
        'Bazen harita üzerinde yüklenmeyip gri kalan kareler artık birkaç '
        'saniye içinde otomatik olarak yeniden yükleniyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.5 beta',
    date: '2026-07-27',
    note:
        'Haritadaki mola noktaları artık isteğe bağlı: sağ alttaki mola '
        'düğmesiyle açıp kapatabilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v1.3.4 beta',
    date: '2026-07-27',
    note:
        'Tespit edilen molalar artık haritada turuncu bir noktayla '
        'işaretleniyor; noktaya dokununca o konuma yakınlaşılıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.3 beta',
    date: '2026-07-27',
    note:
        'Haritayı iki parmakla döndürdüğünüzde artık sağ altta bir pusula '
        'düğmesi çıkıyor; ona dokununca harita kuzeye göre yeniden '
        'hizalanıyor.',
  ),
  ChangelogEntry(
    version: 'v1.3.2 beta',
    date: '2026-07-27',
    note:
        'Dil seçici artık harita ekranında da mevcut (üst çubuğun sağında, '
        'dünya simgesi). Rota listesi ekranındaki dil simgesi hâlâ orada.',
  ),
  ChangelogEntry(
    version: 'v0.4.1 beta',
    date: '2026-07-27',
    note:
        'Çok günlük rotalarda artık haritada hangi günlerin gösterileceğini '
        'seçebilirsiniz (sadece 1. gün, ya da 3. ve 7. günler gibi) - sağ '
        'alttaki filtre düğmesinden.',
  ),
  ChangelogEntry(
    version: 'v0.4.0 beta',
    date: '2026-07-27',
    note:
        'Uygulama artık Türkçe, İngilizce ve Almanca dillerinde '
        'kullanılabiliyor. Sağ üstteki dil simgesinden dilinizi '
        'seçebilirsiniz.',
  ),
  ChangelogEntry(
    version: 'v0.3.2 beta',
    date: '2026-07-27',
    note:
        'Çok günlük rotalar artık haritada her gün farklı bir renkle '
        'çiziliyor. Analizde yeni "Günlük" sekmesi: her gün için mesafe, '
        'sürüş/mola süresi, maksimum irtifa, tırmanış ve o gün geçilen '
        'ülkeler.',
  ),
  ChangelogEntry(
    version: 'v0.3.0 beta',
    date: '2026-07-27',
    note:
        'Haritada katman seçimi eklendi: sağ alttaki katman ikonuna basarak '
        'Sokak, Sade/Siyasi, Koyu, Uydu ve Topografik harita türleri '
        'arasında geçiş yapabilirsin. Seçimin hatırlanır.',
  ),
  ChangelogEntry(
    version: 'v0.2.9 beta',
    date: '2026-07-27',
    note:
        'İçe aktarılan rotanın ismi artık dosya adını önceliyor - GPX/KML '
        'dosyasının içine gömülü genel isimler (ör. "Track 219") artık '
        'senin verdiğin dosya adının önüne geçmiyor.',
  ),
  ChangelogEntry(
    version: 'v0.2.8 beta',
    date: '2026-07-27',
    note:
        'GitHub Pages derlemesinde service worker kapatıldı; eski sürüm '
        'takılı kalmasın diye. Hâlâ eski badge görürsen: site verilerini '
        'temizle veya gizli pencerede aç.',
  ),
  ChangelogEntry(
    version: 'v0.2.7 beta',
    date: '2026-07-27',
    note:
        'KML ayrıştırıcı güçlendirildi: iç içe Folder/MultiGeometry, '
        'birden fazla LineString, gx:Track ve waypoint\'ler. run_dev_web.bat '
        'port 8080\'i başlamadan önce temizler.',
  ),
  ChangelogEntry(
    version: 'v0.2.4 beta',
    date: '2026-07-27',
    note:
        'Web sürümü GitHub Pages üzerinde yayında: '
        'https://alid67-git.github.io/RideAtlas/ — GPX\'ler tarayıcıda '
        'saklanır (cihaz başına). Analiz sekmeleri: Özet, Yükseklik, '
        'Güzergâh, Molalar, Hava.',
  ),
  ChangelogEntry(
    version: 'v0.2.2 beta',
    date: '2026-07-27',
    note:
        'GitHub Actions ile GitHub Pages\'e otomatik yayınlama eklendi - '
        'depo public yapılıp Pages açıldığında, her push sonrası site '
        'birkaç dakika içinde otomatik güncellenecek.',
  ),
  ChangelogEntry(
    version: 'v0.2.1 beta',
    date: '2026-07-25',
    note:
        'build_web.bat artık --pwa-strategy=none ile derliyor: Flutter\'ın '
        'service worker önbelleklemesi kapatıldı, böylece yeni bir derleme '
        'sonrası eski sürümün tarayıcıda takılı kalması sorunu çözülüyor.',
  ),
  ChangelogEntry(
    version: 'v0.2.0 beta',
    date: '2026-07-25',
    note:
        'KML desteği eklendi: artık .gpx yanında .kml dosyaları da içe '
        'aktarılabiliyor. Paylaş butonuna basınca artık GPX mi KML mi '
        'istediğin soruluyor. Haritanın ilk açılışta boş gelme sorununa '
        'yönelik ek bir düzeltme daha yapıldı.',
  ),
  ChangelogEntry(
    version: 'v0.1.12 beta',
    date: '2026-07-25',
    note:
        '"GPX İçe Aktar" butonu sadece rota listesi ekranında vardı; şimdi '
        'haritadaki "Rotalar" penceresine de eklendi, listeye dönmeden yeni '
        'GPX ekleyebilirsin.',
  ),
  ChangelogEntry(
    version: 'v0.1.11 beta',
    date: '2026-07-25',
    note:
        'build_web.bat düzeltildi: "call" eksikti, bu yüzden pub get '
        'sonrası derleme adımı hiç çalışmıyordu.',
  ),
  ChangelogEntry(
    version: 'v0.1.10',
    date: '2026-07-25',
    note:
        'Açılış artık çok daha hızlı: build_web.bat ile bir kez derleyip '
        'run_web.bat ile anında açabilirsin (her seferinde yeniden '
        'derlemiyor).',
  ),
  ChangelogEntry(
    version: 'v0.1.9',
    date: '2026-07-25',
    note:
        'Harita artık ilk açılışta da tam yükleniyor (önceden '
        'yakınlaştırma butonuna basmak gerekiyordu). Analiz butonu üst '
        'çubuğa taşındı. Rota değiştirme penceresinden artık yeniden '
        'adlandırma/silme de yapılabiliyor.',
  ),
  ChangelogEntry(
    version: 'v0.1.8',
    date: '2026-07-25',
    note:
        'Analiz paneli artık ortada, derli toplu bir pencere olarak '
        'açılıyor (alttan açılan panel yerine). Harita ekranındaki liste '
        'butonu da artık geçerli haritayı kapatmadan diğer rotaların '
        'listesini ortada bir pencerede açıyor.',
  ),
  ChangelogEntry(
    version: 'v0.1.7',
    date: '2026-07-25',
    note:
        'Haritaya yakınlaştırma/uzaklaştırma butonları eklendi. Analiz '
        'paneli küçültüldü ve min/maks irtifa artık ayrı kartlarda '
        'gösteriliyor.',
  ),
  ChangelogEntry(
    version: 'v0.1.6',
    date: '2026-07-25',
    note:
        'Harita karoları artık yükleniyor (web\'de CORS sorunu veren OSM '
        'sunucusu yerine CARTO kullanılıyor). Analiz paneli yeniden '
        'düzenlendi: büyük özet sayılar ve yükseklik grafiği artık en '
        'üstte, daha görsel.',
  ),
  ChangelogEntry(
    version: 'v0.1.5',
    date: '2026-07-25',
    note:
        'Harita artık tüm ekranı kaplıyor (önceki sürümde üstte küçük '
        'kalıyordu). Büyük GPX dosyaları için depolama ayrıca iyileştirildi.',
  ),
  ChangelogEntry(
    version: 'v0.1.4',
    date: '2026-07-25',
    note: 'Harita boyutu düzeltildi.',
  ),
  ChangelogEntry(
    version: 'v0.1.3',
    date: '2026-07-25',
    note: 'Hive depolama eklendi.',
  ),
];
