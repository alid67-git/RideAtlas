/// Detailed, localized user-facing help text describing every feature of
/// the app. Kept as plain Dart data (like changelog.dart) instead of ARB
/// entries because these are long paragraphs, not short UI labels.
class HelpSection {
  const HelpSection({required this.title, required this.body});

  final String title;
  final String body;
}

List<HelpSection> helpSections(String languageCode) {
  switch (languageCode) {
    case 'en':
      return _helpSectionsEn;
    case 'de':
      return _helpSectionsDe;
    default:
      return _helpSectionsTr;
  }
}

const _helpSectionsTr = <HelpSection>[
  HelpSection(
    title: 'Rota içe aktarma',
    body:
        'Ana ekrandaki liste ikonuyla rota listesine gidip "GPX/KML/KMZ İçe '
        'Aktar" ile telefonunuzdaki veya bilgisayarınızdaki bir rota '
        'dosyasını yükleyebilirsiniz. GPX, KML ve KMZ formatlarının hepsi '
        'desteklenir; hangi formatta olursa olsun rota otomatik tanınır ve '
        'aynı şekilde haritada gösterilir. Dosya seçme ekranından tek '
        'seferde birden fazla dosya da seçebilirsiniz - hepsi arka arkaya '
        'içe aktarılır ve sonunda kaç tanesinin eklendiğini, kaç tanesinin '
        'atlandığını (yanlış format, bozuk dosya vb.) gösteren kısa bir '
        'özet çıkar. Aynı rota (nokta bazında aynı iz) daha önce zaten '
        'kayıtlıysa tekrar eklenmez; "zaten kayıtlı" uyarısıyla doğrudan '
        'mevcut kayıt açılır. Android\'de dosya yöneticisinde veya başka '
        'bir uygulamanın paylaş menüsünde bir GPX/KML/KMZ dosyasına '
        '"Şununla aç" dediğinizde RideAtlas listede çıkar; seçilince dosya '
        'otomatik içeri alınır ve haritada açılır.',
  ),
  HelpSection(
    title: 'Rota listesi, seçim ve rota önizlemeleri',
    body:
        'Rota listesindeki her satırın solunda bir seçim kutucuğu, hemen '
        'yanında da o rotanın gerçek şekline göre çizilmiş küçük bir '
        'taslak (mini harita yerine) bulunur - haritayı yüklemeden bile '
        'rotanın nasıl bir güzergâh olduğunu bir bakışta ayırt '
        'edebilirsiniz. Kutucuklar her zaman görünür; ayrı bir "seçim '
        'moduna" girmeye gerek yoktur. Üstteki başlık çubuğunda tüm '
        'rotaları tek dokunuşla seçen/kaldıran bir "Hepsi" kutucuğu vardır. '
        'Bir veya daha fazla rota seçtiğinizde alttaki tuşlarla seçilenleri '
        'haritada birlikte gösterebilir veya silebilirsiniz; iki ya da daha '
        'fazlasını seçtiğinizde ayrıca "Birleştir" seçeneği çıkar - '
        'örneğin birkaç günlük bir gezinin her günü ayrı kaydedildiyse, '
        'seçilenler ilk GPS zamanına göre otomatik sıralanıp tek bir '
        'rotada birleştirilir; bir isim sorulur, orijinal rotalar '
        'silinmez, sadece isimlerine "(birleştirildi)" eklenir; üzerlerindeki '
        'fotoğraf/videolar da yeni rotaya kopyalanır. Her satırın sağındaki '
        '⋮ menüsünden rotayı yeniden adlandırabilir, silebilir veya '
        '"Anormal noktaları düzenle" ile o rotadaki GPS sıçramalarını '
        'gözden geçirebilirsiniz (aşağıda ayrı başlık).',
  ),
  HelpSection(
    title: 'Harita görünümü',
    body:
        'Bir rotayı açtığınızda harita üzerinde güzergâh çizilir ve '
        'otomatik olarak tüm rotayı ekrana sığdıracak şekilde '
        'yakınlaştırılır. Sağ alttaki "tüm izi göster" ikonuyla '
        'istediğiniz an bu sığdırmaya geri dönebilirsiniz - harita '
        'döndürülmüş olsa bile önce kuzeye çevirip doğru şekilde sığdırır. '
        'Sağ alttaki başka bir ikonla harita türünü (sokak, uydu, topo, '
        'koyu, sade) değiştirebilirsiniz. Birden çok günlük rotalarda gün '
        'filtresiyle sadece belirli günleri gösterebilir, pusula ikonuyla '
        'haritayı kuzeye çevirebilirsiniz. Mola ve geceleme noktaları '
        'başlangıçta gizlidir; üst çubuktaki düğmeyle istediğiniz zaman '
        'açıp kapatabilirsiniz. Fotoğraf/video konumlarını gösteren ayrı '
        'bir düğme de aynı çubukta yer alır.',
  ),
  HelpSection(
    title: 'Detaylı analiz',
    body:
        'Harita ekranındaki grafik ikonuyla rotanın detaylı analizini '
        'açarsınız: Özet (mesafe, süre, ortalama/maksimum hız), Yükseklik '
        'profili (tırmanış, iniş, en yüksek/en düşük nokta), Güzergâh '
        '(geçilen ülkeler sırasıyla), Molalar (20 dakikadan uzun '
        'duraklamalar ve gecelemeler), Hava durumu (rota boyunca günlük '
        'hava koşulları, internet gerektirir) ve Günlük (rota birden fazla '
        'güne yayılıyorsa gün gün özet - her günün kendi mesafesi, süresi '
        've sürüş/mola dağılımı). Güzergâh, Molalar, Hava durumu ve Günlük '
        'sekmeleri ilk açıldıklarında hesaplanır; bir kez hesaplandıktan '
        'sonra tekrar tekrar yeniden işlenmez.',
  ),
  HelpSection(
    title: 'Fotoğraf ve video ekleme',
    body:
        'Bir rotayı açtığınızda fotoğraf makinesi ikonuyla fotoğraf veya '
        'video ekleyebilirsiniz; kamera veya galeri seçeneği tek noktadan '
        'sunulur, galeriden hem fotoğraf hem video aynı anda seçilebilir. '
        'Fotoğrafta konum bilgisi (EXIF) varsa çekildiği nokta haritada '
        'otomatik işaretlenir. Konum bilgisi yoksa (bazı tarayıcılar veya '
        'video dosyaları bu bilgiyi içermez) haritadan elle nokta '
        'seçebilir ya da bu adımı atlayabilirsiniz. Eklenen tüm '
        'fotoğraf/videolar ekranın altındaki şeritte görünür ve dokununca '
        'büyütülerek izlenebilir; büyütülmüş görünümde silme düğmesi de '
        'bulunur. Bir kayıt bitirilip kaydedildiğinde, o sürüş süresince '
        'galeriye eklenmiş fotoğraf/videolar varsa otomatik olarak '
        'listelenir ve hangilerini rotaya eklemek istediğiniz sorulur - '
        'konumları mümkünse otomatik bulunur (galeri GPS bilgisi, yoksa '
        'EXIF, o da yoksa kayıt anındaki GPS izinden). Haritada, '
        'fotoğraf/video konumlarını gösteren veya gizleyen ayrı bir düğme '
        'bulunur; bir pine dokununca o an haritada görünen tüm medya '
        'önizleme olarak açılır.',
  ),
  HelpSection(
    title: 'GPS ile canlı rota kaydı',
    body:
        'Ana ekrandaki kırmızı kayıt düğmesiyle canlı GPS kaydı '
        'başlatabilirsiniz. Kayıt başlar başlamaz bilgi paneli açılır: '
        'toplam süre, aktif sürüş süresi, mola süresi, mesafe, ortalama/'
        'maks. hız, yükseklik, toplam çıkış/iniş ve hız/yükseklik '
        'grafikleri tek ekranda; bu kartların sırasını ve hangilerinin '
        'görüneceğini Ayarlar > "Kayıt ekranı kartları" bölümünden '
        'sürükleyerek değiştirebilirsiniz. Bilgi ekranının sol '
        'altındaki harita düğmesiyle, konumunuzu gerçek zamanlı takip '
        'eden ve yön-yukarı (navigasyon gibi) dönen haritaya geçebilir, '
        'oradaki haritanın sol altındaki panel düğmesiyle geri '
        'dönebilirsiniz - iki ekran arasında geçiş her zaman aynı köşeden '
        'olur. Haritanın sol üstünde, geri tuşunun yanında, daha önce '
        'kaydettiğiniz veya içe aktardığınız rotalardan istediğinizi '
        'seçip canlı iz altında referans olarak gösterebileceğiniz bir '
        'tuş bulunur (ör. dün gittiğiniz yolu tekrar izlerken '
        'karşılaştırmak için); hiçbir rota seçmezseniz sadece o anki '
        'kayıt görünür. İstediğiniz zaman duraklatıp devam edebilir, '
        'bitirip bir isimle kaydedebilir veya tamamen silebilirsiniz. '
        'Kayıt ekranından geri çıkmak kaydı durdurmaz; kayıt arka planda '
        'sürerken ekranın kenarında küçük bir kırmızı "REC" düğmesi '
        'belirir, dokunduğunuzda kayıt ekranına geri dönersiniz. '
        'Android\'de kayıt, uygulama küçültülse bile bir bildirimle arka '
        'planda devam eder - bunun için konum izninin "Her zaman izin '
        'ver" olması ve (istediğinizde) pil optimizasyonundan muaf '
        'tutulması gerekir; ikisi de Ayarlar\'dan tek dokunuşla '
        'açılabilir. Web tarayıcısında kayıt sadece sekme ön plandayken '
        've ekran açıkken sürer. Kayıt sırasında çekilen foto/videolar '
        'kaydetme sonrası önerilir. Kaydettiğiniz rotanın Özet sekmesinde '
        'hem net sürüş süresi (bekleme hariç) hem toplam süre (tüm '
        'molalar dahil), hem de kayıt başlangıç/bitiş pil yüzdeleri '
        'görüntülenir.',
  ),
  HelpSection(
    title: 'Otomatik duraklama',
    body:
        'Hızınız yaklaşık 3 saniye boyunca 1.5 km/s\'in altına düşerse '
        'kayıt otomatik olarak duraklar ve ekranda "Otomatik duraklatıldı" '
        'yazısı belirir - trafik ışığında, benzin molasında veya sohbet '
        'ederken kayıt gereksiz yere mesafe/süre eklemeye devam etmez. '
        'Tekrar en az 2.5 km/s hıza çıktığınızda veya durduğunuz noktadan '
        '20 metreden fazla uzaklaştığınızda kayıt kendiliğinden devam '
        'eder - hiçbir düğmeye basmanız gerekmez. Duraklamış haldeyken '
        'telefonu elinize alıp cebe koyarken veya bir binanın yanından '
        'geçerken GPS bazen tek seferlik, fiziksel olarak imkansız bir '
        '1-2 km\'lik anlık sıçrama üretebilir; bu tür tekil sıçramalar '
        'artık göz ardı edilip yalnızca gerçek, sürekli bir hareket '
        'duraklamayı kaldırır - böylece kayıt siz gerçekten yola '
        'çıkmadan yanlışlıkla "devam ediyor" hâline geçmez.',
  ),
  HelpSection(
    title: 'Anormal GPS noktalarını düzenleme',
    body:
        'GPS alıcıları bazen (bina arasında, tünelde, kötü sinyalde) tek '
        'bir kötü ölçümle rotada anlamsız bir "sıçrama" üretebilir. Bu '
        'tür noktalar hem canlı kayıt sırasında hem de bir dosya içe '
        'aktarılırken otomatik olarak tespit edilip harita çiziminden ve '
        'istatistik hesaplarından (mesafe, hız, yükseklik) çıkarılır - '
        'orijinal dosya değişmez. Bir rotayı kalıcı olarak temizlemek '
        'isterseniz, rota listesindeki ⋮ menüsünden "Anormal noktaları '
        'düzenle" seçeneğini açın: tespit edilen her şüpheli nokta, bir '
        'önceki noktaya göre ima ettiği hızla birlikte listelenir; '
        'istediklerinizin işaretini kaldırıp geri kalanları rotadan '
        'kalıcı olarak silebilirsiniz. Rotada şüpheli nokta yoksa bu '
        'ekran "temiz" olduğunu bildirir.',
  ),
  HelpSection(
    title: 'Kesintiye uğrayan kayıtların kurtarılması',
    body:
        'Telefon kilitlenir, uygulama işletim sistemi tarafından '
        'kapatılır veya pil biterse, devam eden bir kayıt kaybolmaz. '
        'Uygulamayı bir sonraki açışınızda RideAtlas kaydı otomatik '
        'olarak kaldığı yerden devam ettirir (kayıttaysa kayıt, '
        'duraklatılmışsa duraklatılmış halde) ve kısa bir bildirimle '
        'haber verir. Elle hiçbir şey yapmanız gerekmez.',
  ),
  HelpSection(
    title: 'Konum izinleri, uydu sayısı ve pil optimizasyonu',
    body:
        'Arka planda kesintisiz kayıt için Android\'de konum izninin '
        '"Her zaman izin ver" olması gerekir; Ayarlar ekranındaki ilgili '
        'düğme sizi doğrudan bu ayara götürür. Aynı ekrandaki "Arka '
        'planda GPS izni" seçeneği, telefonun pil tasarrufu ayarlarının '
        'ekran kapalıyken kaydı durdurmasını engeller - bir kez '
        'açtığınızda tekrar sormaz. Ayarlar\'daki "Uydu sayısını göster" '
        'anahtarını açarsanız, kayıt düğmesinin ve kayıt ekranının '
        'yanında o an telefonun kaç GPS uydusuna bağlı olduğunu gösteren '
        'küçük bir rozet belirir - zayıf sinyal bölgelerinde neden '
        'konumun gecikmeli/kararsız geldiğini anlamanıza yardımcı olur.',
  ),
  HelpSection(
    title: 'Araç ikonu',
    body:
        'Ayarlar > Araç ikonu bölümünden haritadaki "buradayım" '
        'işaretçisini klasik nokta yerine bir motosiklet veya araba '
        'simgesiyle değiştirebilirsiniz; her biri 5 farklı ölçek ve '
        'renk seçeneğiyle gelir. İstatistik kartlarının ikon rengini ve '
        'büyüklüğünü de Ayarlar > "İstatistik ikon görünümü" bölümünden '
        'ayrıca özelleştirebilirsiniz. Seçtiğiniz ikon/renk siz '
        'değiştirene kadar kalıcı olarak kullanılır.',
  ),
  HelpSection(
    title: 'Android Auto',
    body:
        'Telefonda başlattığınız bir kaydı, arabanın ekranından da '
        'görüp kontrol edebilirsiniz: hız, süre ve mesafe orada da '
        'gösterilir; duraklat/devam et ve bitir düğmeleri de çalışır '
        '(sürüş güvenliği kuralları gereği araba ekranından isim '
        'yazılamaz, kayıt otomatik bir isimle kaydedilir). Bunun için '
        'telefon uygulamasının en az bir kez açılmış olması yeterli. '
        'CarPlay desteği şu an yok - Apple\'ın özel izni gerekiyor.',
  ),
  HelpSection(
    title: 'Dışa aktarma',
    body:
        'Harita ekranındaki paylaş ikonuyla açık olan rotayı GPX, KML veya '
        'KMZ formatında dışa aktarabilir, bir dosya adı seçip (varsayılan '
        'olarak rotanın kendi ismi önerilir) başka bir uygulamayla veya '
        'kişiyle paylaşabilirsiniz. Özellikle birleştirilmiş rotalarda '
        '(otomatik "A + B" ismiyle gelenler) farklı bir isim vermek '
        'isteyebilirsiniz.',
  ),
  HelpSection(
    title: 'Uygulama güncellemeleri',
    body:
        'Android\'de yeni sürüm çıkınca uygulama açılışta sorar; tek '
        'düğme "Güncelle" yeterlidir. Sonrası otomatik: indirme yüzdesi '
        'uygulamayı kilitlemeden alttaki banner\'da gösterilir, bitince '
        'kurulum ekranı açılır ve eski uygulama süreci kendini kapatır - '
        'geri kaydırınca eski sürüme değil güncel sürüme dönersiniz. '
        'İstemezseniz diyaloğu kapatın - ana ekranda yine "Güncelle" '
        'banner\'ı kalır, istediğiniz an devam edebilirsiniz. Web sürümü '
        'her ziyarette zaten güncel haliyle yüklenir.',
  ),
  HelpSection(
    title: 'Dil değiştirme',
    body:
        'Ayarlar ekranındaki Dil bölümünden uygulamayı Türkçe, İngilizce '
        'veya Almanca olarak kullanabilirsiniz. Seçiminiz kaydedilir ve bir '
        'sonraki açılışta hatırlanır.',
  ),
];

const _helpSectionsEn = <HelpSection>[
  HelpSection(
    title: 'Importing a route',
    body:
        'From the home screen, tap the list icon to open your routes, then '
        'use "Import GPX/KML/KMZ" to load a route file from your phone or '
        'computer. GPX, KML and KMZ are all supported - whichever format '
        'you import, the route is recognized automatically and shown on '
        'the map the same way. You can also pick several files at once in '
        'the file picker - all of them are imported in one pass, and a '
        'short summary tells you how many were added and how many were '
        'skipped (wrong format, corrupt file, etc.). If the exact same '
        'route (matched point-for-point) is already saved, it isn\'t added '
        'again - a "already saved" notice opens the existing copy '
        'instead. On Android, a GPX/KML/KMZ file offered through a file '
        'manager or another app\'s share menu lists RideAtlas as an '
        '"Open with" option; picking it imports the file automatically '
        'and opens it on the map.',
  ),
  HelpSection(
    title: 'Route list, selection and thumbnails',
    body:
        'Every row in the route list has a selection checkbox on the '
        'left, and next to it a small thumbnail traced from that route\'s '
        'own shape (instead of a generic icon) - you can tell routes '
        'apart at a glance without opening the map. Checkboxes are always '
        'visible; there\'s no separate "selection mode" to switch into '
        'first. A "select all" checkbox in the title bar picks or clears '
        'every route in one tap. With one or more routes selected, the '
        'buttons at the bottom show them together on the map or delete '
        'them; selecting two or more also reveals a "Merge" option - '
        'useful when a multi-day trip was recorded as separate rides per '
        'day. The selection is automatically ordered by each route\'s own '
        'first GPS timestamp and combined into one new route (you\'re '
        'asked for a name); the originals aren\'t deleted, just renamed '
        'with a "(merged)" suffix, and any photos/videos on them are '
        'copied onto the new route too. The ⋮ menu on each row lets you '
        'rename or delete a route, or open "Edit anomalous points" to '
        'review GPS jumps on that specific route (see below).',
  ),
  HelpSection(
    title: 'Map view',
    body:
        'Opening a route draws its path on the map and automatically '
        'zooms to fit the whole thing on screen. The "fit route" icon in '
        'the bottom right returns to that framing any time - even if '
        'the map has been rotated, it resets to north-up first so the '
        'fit is always correct. Another icon in the bottom right switches '
        'the map type (street, satellite, topo, dark, clean). For routes '
        'spanning several days, a day filter lets you show only certain '
        'days, and the compass icon resets the map to north-up. Stop and '
        'overnight-stay markers are hidden by default - toggle them on or '
        'off any time with the button in the top bar, and a separate '
        'button in the same bar shows or hides photo/video locations.',
  ),
  HelpSection(
    title: 'Detailed analysis',
    body:
        'The chart icon on the map screen opens a detailed analysis of the '
        'route: Overview (distance, duration, average/max speed), '
        'Elevation profile (climb, descent, highest/lowest point), Route '
        '(countries crossed, in order), Stops (pauses longer than 20 '
        'minutes and overnight stays), Weather (daily conditions along '
        'the route, needs internet) and Daily (a day-by-day breakdown for '
        'multi-day routes - each day\'s own distance, duration and riding/'
        'rest split). Route, Stops, Weather and Daily are computed the '
        'first time you open them, not recomputed on every rebuild.',
  ),
  HelpSection(
    title: 'Adding photos and videos',
    body:
        'While a route is open, the camera icon lets you add a photo or '
        'video - camera and gallery are offered from one single menu, and '
        'picking from the gallery can select photos and videos together in '
        'one go. If a photo carries location data (EXIF), the spot it was '
        'taken at is marked on the map automatically. When there\'s no '
        'location data (some browsers strip it, and video files usually '
        'don\'t carry it), you can pick a point on the map by hand or skip '
        'that step entirely. Everything you\'ve added shows up in a strip '
        'at the bottom of the screen, and tapping an item opens it full '
        'screen, where a delete button is also available. When you finish '
        'and save a recording, any photos/videos your gallery gained '
        'during that ride are found automatically and you\'re asked which '
        'ones to attach to the route - locations are filled in '
        'automatically when possible (gallery GPS data first, then EXIF, '
        'then the ride\'s own recorded track). The map has a separate '
        'button to show or hide photo/video locations; tapping a pin opens '
        'a preview of every item currently visible on the map.',
  ),
  HelpSection(
    title: 'Live GPS recording',
    body:
        'The red record button on the home screen starts a live GPS '
        'recording. As soon as it starts, an info page opens: total '
        'duration, active riding time, rest time, distance, average/max '
        'speed, altitude, total climb/descent, and speed/elevation charts, '
        'all on one screen - you can reorder these cards or hide the ones '
        'you don\'t want from Settings > "Recording screen cards". The map '
        'button in the bottom left of the info screen switches to a live, '
        'heading-up rotating map (like turn-by-turn navigation); the same '
        'bottom-left spot on the map switches back, so the toggle is '
        'always in the same corner in both directions. In the top left of '
        'the map, next to the back button, a route icon lets you pick one '
        'or more previously saved or imported routes to overlay as a '
        'reference under your live line (handy for retracing a road you '
        'rode before) - pick none and only the current recording shows. '
        'You can pause and resume at any time, finish and save the ride '
        'under a name, or discard it entirely. Leaving the recording '
        'screen doesn\'t stop the recording - while it runs in the '
        'background, a small red "REC" button appears on the edge of the '
        'screen; tap it to jump back. On Android, recording keeps running '
        'in the background with a notification even if you minimize the '
        'app - this needs "Allow all the time" location permission and, '
        'if you want, an exemption from battery optimization; both are '
        'one tap away in Settings. In a web browser, recording only '
        'continues while the tab is in the foreground and the screen is '
        'on. Photos/videos taken during the ride are offered after '
        'saving. The saved ride\'s Overview tab shows both a net riding '
        'time (waits excluded) and a total time (every stop included), '
        'plus the battery percentage at the start and end of the '
        'recording.',
  ),
  HelpSection(
    title: 'Auto-pause',
    body:
        'If your speed stays under 1.5 km/h for about 3 seconds, '
        'recording pauses itself and "Auto-paused" appears on screen - so '
        'a red light, fuel stop or roadside chat doesn\'t keep padding '
        'your distance and time. It resumes on its own as soon as you '
        'reach at least 2.5 km/h again, or move more than 20 meters from '
        'where you stopped - no button to tap. While paused, picking up '
        'the phone or walking past a building can make the GPS chip '
        'report a single, physically impossible 1-2 km jump for a moment; '
        'a lone glitch like that is now ignored, and only genuine, '
        'sustained movement resumes the recording - so it won\'t '
        'mistakenly look like you\'re moving again before you actually '
        'are.',
  ),
  HelpSection(
    title: 'Editing anomalous GPS points',
    body:
        'GPS receivers occasionally produce a single bad reading (between '
        'buildings, in a tunnel, with a weak signal) that shows up as a '
        'nonsense "jump" on the route. These are detected automatically, '
        'both during live recording and when importing a file, and '
        'excluded from the drawn line and every statistic (distance, '
        'speed, altitude) - the original file is never touched. To clean '
        'up a route permanently, open "Edit anomalous points" from the ⋮ '
        'menu on any route in the list: every flagged point is listed '
        'along with the speed it implies relative to the previous point; '
        'uncheck any you want to keep and delete the rest from the route '
        'for good. If a route has no suspicious points, this screen says '
        'so.',
  ),
  HelpSection(
    title: 'Recovering an interrupted recording',
    body:
        'If your phone locks up, the OS kills the app, or the battery '
        'dies, an in-progress recording isn\'t lost. The next time you '
        'open RideAtlas, it automatically resumes right where it left off '
        '(recording if it was recording, paused if it was paused) and '
        'tells you with a short notice. There\'s nothing to do by hand.',
  ),
  HelpSection(
    title: 'Location permission, satellite count and battery',
    body:
        'Uninterrupted background recording on Android needs "Allow all '
        'the time" location permission - the matching row in Settings '
        'takes you straight to that system setting. The "Background GPS '
        'permission" option on the same screen stops the phone\'s own '
        'battery-saving settings from killing the recording once the '
        'screen turns off - grant it once and it won\'t ask again. '
        'Turning on "Show satellite count" in Settings adds a small badge '
        'next to the record button and on the recording screen showing '
        'how many GPS satellites the phone is currently locked onto - '
        'useful for understanding why a fix is slow or unstable in a '
        'weak-signal area.',
  ),
  HelpSection(
    title: 'Vehicle icon',
    body:
        'Settings > Vehicle icon lets you replace the "you are here" '
        'marker on the map with a motorcycle or car icon instead of the '
        'classic dot, each in 5 different scale/color presets. Statistic '
        'card icon color and size can be customized separately under '
        'Settings > "Statistic icon appearance". Your choices stay until '
        'you change them again.',
  ),
  HelpSection(
    title: 'Android Auto',
    body:
        'A recording started on the phone can also be viewed and '
        'controlled from the car\'s own screen: speed, duration and '
        'distance show there too, and pause/resume and finish work as '
        'well (driver-safety rules mean the car screen can\'t type a '
        'name, so it saves under an automatic one). The phone app just '
        'needs to have been opened at least once first. There\'s no '
        'CarPlay support yet - that needs a special entitlement from '
        'Apple.',
  ),
  HelpSection(
    title: 'Exporting',
    body:
        'The share icon on the map screen exports the open route as GPX, '
        'KML or KMZ - pick a file name (the route\'s own name is '
        'suggested by default) and share it with another app or another '
        'person. Merged routes (with an automatic "A + B" name) are a '
        'common case where you\'ll want to type something different.',
  ),
  HelpSection(
    title: 'App updates',
    body:
        'On Android, the app asks at launch when a new version is out - '
        'one "Update" tap is enough. Everything after that runs in the '
        'background without locking the app: download progress shows in '
        'a bottom banner, the installer opens automatically once it\'s '
        'done, and the old app process closes itself - swiping back lands '
        'you in the new version, not the stale one. Dismiss the dialog '
        'and a home-screen banner still offers the same single Update '
        'button whenever you\'re ready. The web version always loads the '
        'latest build on every visit.',
  ),
  HelpSection(
    title: 'Changing the language',
    body:
        'The Language section in Settings lets you switch the app between '
        'Turkish, English and German. Your choice is saved and remembered '
        'the next time you open the app.',
  ),
];

const _helpSectionsDe = <HelpSection>[
  HelpSection(
    title: 'Route importieren',
    body:
        'Tippen Sie auf dem Startbildschirm auf das Listensymbol, um Ihre '
        'Routen zu öffnen, und laden Sie über "GPX/KML/KMZ importieren" '
        'eine Routendatei von Ihrem Telefon oder Computer. GPX, KML und '
        'KMZ werden alle unterstützt - unabhängig vom Format wird die '
        'Route automatisch erkannt und auf die gleiche Weise auf der '
        'Karte angezeigt. In der Dateiauswahl können Sie auch mehrere '
        'Dateien gleichzeitig auswählen - alle werden nacheinander '
        'importiert, und am Ende zeigt eine kurze Zusammenfassung, wie '
        'viele hinzugefügt und wie viele übersprungen wurden (falsches '
        'Format, beschädigte Datei usw.). Ist genau dieselbe Route (Punkt '
        'für Punkt identisch) bereits gespeichert, wird sie nicht erneut '
        'hinzugefügt - ein Hinweis "bereits gespeichert" öffnet stattdessen '
        'die vorhandene Kopie. Unter Android erscheint RideAtlas im '
        '"Öffnen mit"-Menü eines Dateimanagers oder der Teilen-Funktion '
        'einer anderen App für GPX/KML/KMZ-Dateien; die Auswahl importiert '
        'die Datei automatisch und öffnet sie auf der Karte.',
  ),
  HelpSection(
    title: 'Routenliste, Auswahl und Vorschaubilder',
    body:
        'Jede Zeile in der Routenliste hat links ein Auswahlkästchen und '
        'daneben ein kleines Vorschaubild, das aus der tatsächlichen Form '
        'der Route gezeichnet wird (statt eines allgemeinen Symbols) - so '
        'erkennen Sie Routen auf einen Blick, ohne die Karte zu öffnen. '
        'Die Kästchen sind immer sichtbar; es gibt keinen separaten '
        '"Auswahlmodus", in den man zuerst wechseln muss. Ein '
        '"Alle auswählen"-Kästchen in der Titelleiste wählt oder löscht '
        'alle Routen mit einem Tipp. Bei einer oder mehreren ausgewählten '
        'Routen zeigen die Schaltflächen unten sie gemeinsam auf der '
        'Karte an oder löschen sie; bei zwei oder mehr ausgewählten '
        'Routen erscheint zusätzlich "Zusammenführen" - praktisch, wenn '
        'eine mehrtägige Reise als separate Fahrten pro Tag aufgezeichnet '
        'wurde. Die Auswahl wird automatisch nach dem ersten '
        'GPS-Zeitstempel jeder Route sortiert und zu einer neuen Route '
        'zusammengeführt (ein Name wird abgefragt); die Originale werden '
        'nicht gelöscht, nur mit dem Zusatz "(zusammengeführt)" '
        'umbenannt, und Fotos/Videos daran werden ebenfalls auf die neue '
        'Route kopiert. Über das ⋮-Menü jeder Zeile können Sie eine Route '
        'umbenennen, löschen oder mit "Anomale Punkte bearbeiten" '
        'GPS-Ausreißer dieser Route überprüfen (siehe unten).',
  ),
  HelpSection(
    title: 'Kartenansicht',
    body:
        'Beim Öffnen einer Route wird die Strecke auf der Karte '
        'eingezeichnet und automatisch so gezoomt, dass sie ganz auf den '
        'Bildschirm passt. Das Symbol "Route einpassen" unten rechts '
        'kehrt jederzeit zu dieser Ansicht zurück - selbst wenn die Karte '
        'gedreht wurde, wird sie zuerst nach Norden ausgerichtet, damit '
        'die Einpassung immer korrekt ist. Ein weiteres Symbol unten '
        'rechts wechselt den Kartentyp (Straße, Satellit, Topo, dunkel, '
        'einfach). Bei mehrtägigen Routen können Sie mit dem Tagesfilter '
        'nur bestimmte Tage anzeigen, und das Kompasssymbol richtet die '
        'Karte wieder nach Norden aus. Pausen- und Übernachtungsmarker '
        'sind standardmäßig ausgeblendet - schalten Sie sie jederzeit über '
        'die Schaltfläche in der oberen Leiste ein oder aus; eine weitere '
        'Schaltfläche in derselben Leiste zeigt oder verbirgt Foto-/'
        'Videostandorte.',
  ),
  HelpSection(
    title: 'Detaillierte Analyse',
    body:
        'Das Diagrammsymbol auf dem Kartenbildschirm öffnet eine '
        'detaillierte Analyse der Route: Übersicht (Distanz, Dauer, '
        'Durchschnitts-/Höchstgeschwindigkeit), Höhenprofil (Anstieg, '
        'Abstieg, höchster/niedrigster Punkt), Strecke (durchquerte '
        'Länder in Reihenfolge), Pausen (Stopps länger als 20 Minuten und '
        'Übernachtungen), Wetter (tägliche Bedingungen entlang der Route, '
        'benötigt Internet) und Täglich (eine Tag-für-Tag-Aufschlüsselung '
        'bei mehrtägigen Routen - Distanz, Dauer sowie Fahr-/Pausenzeit '
        'jedes einzelnen Tages). Strecke, Pausen, Wetter und Täglich '
        'werden beim ersten Öffnen berechnet, nicht bei jedem erneuten '
        'Aufbau neu ermittelt.',
  ),
  HelpSection(
    title: 'Fotos und Videos hinzufügen',
    body:
        'Bei geöffneter Route können Sie über das Kamerasymbol ein Foto '
        'oder Video hinzufügen - Kamera und Galerie werden in einem '
        'einzigen Menü angeboten, und bei der Auswahl aus der Galerie '
        'können Fotos und Videos gemeinsam in einem Schritt ausgewählt '
        'werden. Enthält ein Foto Standortdaten (EXIF), wird der '
        'Aufnahmeort automatisch auf der Karte markiert. Fehlen '
        'Standortdaten (manche Browser entfernen sie, und Videodateien '
        'enthalten sie meist ohnehin nicht), können Sie den Ort manuell auf '
        'der Karte auswählen oder diesen Schritt überspringen. Alle '
        'hinzugefügten Fotos/Videos erscheinen in einer Leiste am unteren '
        'Bildschirmrand; ein Tipp darauf öffnet sie in Vollbild, wo auch '
        'eine Löschfunktion verfügbar ist. Wird eine Aufzeichnung beendet '
        'und gespeichert, werden Fotos/Videos, die während der Fahrt zur '
        'Galerie hinzugefügt wurden, automatisch gefunden - Sie wählen '
        'dann aus, welche der Route hinzugefügt werden sollen; Standorte '
        'werden nach Möglichkeit automatisch ausgefüllt (zuerst '
        'Galerie-GPS-Daten, dann EXIF, dann die eigene aufgezeichnete '
        'Strecke der Fahrt). Auf der Karte gibt es eine eigene '
        'Schaltfläche, um Foto-/Videostandorte ein- oder auszublenden; '
        'ein Tipp auf einen Pin öffnet eine Vorschau aller aktuell auf '
        'der Karte sichtbaren Elemente.',
  ),
  HelpSection(
    title: 'Live-GPS-Aufzeichnung',
    body:
        'Die rote Aufzeichnungstaste auf dem Startbildschirm startet eine '
        'Live-GPS-Aufzeichnung. Sobald sie beginnt, öffnet sich ein '
        'Infopanel: Gesamtdauer, aktive Fahrzeit, Pausenzeit, Distanz, '
        'Durchschnitts-/Höchstgeschwindigkeit, Höhe, Gesamtanstieg/-abstieg '
        'sowie Geschwindigkeits-/Höhendiagramme - alles auf einem '
        'Bildschirm; Reihenfolge und Sichtbarkeit dieser Karten lassen '
        'sich unter Einstellungen > "Karten der Aufzeichnungsseite" per '
        'Ziehen anpassen. Die Kartenschaltfläche unten links auf der '
        'Infoseite wechselt zu einer live, nach Fahrtrichtung gedrehten '
        'Karte (wie bei einer Navigation); dieselbe Position unten links '
        'auf der Karte führt zurück - der Wechsel erfolgt immer an derselben '
        'Ecke, in beide Richtungen. Oben links auf der Karte, neben der '
        'Zurück-Taste, lässt eine Routen-Schaltfläche Sie eine oder '
        'mehrere zuvor gespeicherte oder importierte Routen als Referenz '
        'unter Ihrer Live-Linie einblenden (praktisch, um eine früher '
        'gefahrene Strecke nachzuverfolgen) - wählen Sie keine aus, wird '
        'nur die aktuelle Aufzeichnung angezeigt. Sie können jederzeit '
        'pausieren und fortsetzen, die Fahrt unter einem Namen speichern '
        'oder verwerfen. Das Verlassen des Aufzeichnungsbildschirms stoppt '
        'die Aufzeichnung nicht - während sie im Hintergrund weiterläuft, '
        'erscheint eine kleine rote "REC"-Schaltfläche am Bildschirmrand; '
        'tippen Sie darauf, um zurückzukehren. Unter Android läuft die '
        'Aufzeichnung mit einer Benachrichtigung auch im Hintergrund '
        'weiter, wenn Sie die App minimieren - dafür ist die '
        'Standortberechtigung "Immer zulassen" nötig sowie, wenn '
        'gewünscht, eine Ausnahme von der Akku-Optimierung; beides ist in '
        'den Einstellungen mit einem Tipp erreichbar. Im Webbrowser läuft '
        'die Aufzeichnung nur, solange der Tab im Vordergrund und der '
        'Bildschirm an ist. Fotos/Videos, die während der Fahrt '
        'aufgenommen wurden, werden nach dem Speichern angeboten. Im '
        'Übersicht-Tab der gespeicherten Fahrt werden sowohl eine '
        'Nettofahrzeit (ohne Wartezeiten) als auch eine Gesamtzeit (mit '
        'allen Pausen) sowie der Akkustand bei Start und Ende der '
        'Aufzeichnung angezeigt.',
  ),
  HelpSection(
    title: 'Automatische Pause',
    body:
        'Bleibt Ihre Geschwindigkeit etwa 3 Sekunden lang unter 1,5 km/h, '
        'pausiert die Aufzeichnung von selbst und "Automatisch pausiert" '
        'erscheint auf dem Bildschirm - so verlängert eine rote Ampel, '
        'ein Tankstopp oder ein Gespräch am Straßenrand nicht unnötig '
        'Distanz und Zeit. Sie wird von selbst fortgesetzt, sobald Sie '
        'wieder mindestens 2,5 km/h erreichen oder sich mehr als 20 Meter '
        'von der Stelle entfernen, an der Sie angehalten haben - ohne '
        'Tastendruck. Während der Pause kann das GPS beim Hochnehmen des '
        'Telefons oder beim Vorbeigehen an einem Gebäude kurzzeitig einen '
        'einzelnen, physikalisch unmöglichen Sprung von 1-2 km melden; '
        'ein solcher einzelner Ausreißer wird jetzt ignoriert, und nur '
        'eine echte, anhaltende Bewegung setzt die Aufzeichnung fort - so '
        'sieht es nicht fälschlich so aus, als würden Sie sich schon '
        'wieder bewegen, bevor es tatsächlich so ist.',
  ),
  HelpSection(
    title: 'Anomale GPS-Punkte bearbeiten',
    body:
        'GPS-Empfänger liefern gelegentlich (zwischen Gebäuden, im Tunnel, '
        'bei schwachem Signal) eine einzelne fehlerhafte Messung, die als '
        'unsinniger "Sprung" auf der Route erscheint. Solche Punkte werden '
        'automatisch erkannt - sowohl bei der Live-Aufzeichnung als auch '
        'beim Importieren einer Datei - und aus der gezeichneten Linie und '
        'allen Statistiken (Distanz, Geschwindigkeit, Höhe) '
        'ausgeschlossen; die Originaldatei bleibt unverändert. Um eine '
        'Route dauerhaft zu bereinigen, öffnen Sie über das ⋮-Menü einer '
        'beliebigen Route in der Liste "Anomale Punkte bearbeiten": jeder '
        'markierte Punkt wird zusammen mit der daraus gegenüber dem '
        'vorherigen Punkt resultierenden Geschwindigkeit aufgelistet; '
        'deaktivieren Sie die, die Sie behalten möchten, und löschen Sie '
        'den Rest endgültig aus der Route. Hat eine Route keine '
        'verdächtigen Punkte, meldet dieser Bildschirm das entsprechend.',
  ),
  HelpSection(
    title: 'Unterbrochene Aufzeichnungen wiederherstellen',
    body:
        'Sperrt sich Ihr Telefon, beendet das Betriebssystem die App oder '
        'geht der Akku leer, geht eine laufende Aufzeichnung nicht '
        'verloren. Beim nächsten Öffnen von RideAtlas wird sie automatisch '
        'genau dort fortgesetzt, wo sie unterbrochen wurde (aufzeichnend, '
        'wenn sie gerade aufzeichnete, pausiert, wenn sie pausiert war), '
        'und ein kurzer Hinweis informiert Sie darüber. Sie müssen nichts '
        'von Hand tun.',
  ),
  HelpSection(
    title: 'Standortberechtigung, Satellitenanzahl und Akku',
    body:
        'Für eine unterbrechungsfreie Aufzeichnung im Hintergrund ist unter '
        'Android die Standortberechtigung "Immer zulassen" nötig - die '
        'entsprechende Zeile in den Einstellungen führt direkt zu dieser '
        'Systemeinstellung. Die Option "Standort im Hintergrund" auf '
        'demselben Bildschirm verhindert, dass die Akku-Spareinstellungen '
        'des Telefons die Aufzeichnung beenden, sobald der Bildschirm '
        'ausgeht - einmal erteilt, wird nicht erneut gefragt. Schalten Sie '
        '"Satellitenanzahl anzeigen" in den Einstellungen ein, erscheint '
        'neben der Aufzeichnungstaste und auf dem Aufzeichnungsbildschirm '
        'ein kleines Abzeichen mit der Anzahl der GPS-Satelliten, mit '
        'denen das Telefon gerade verbunden ist - nützlich, um zu '
        'verstehen, warum eine Positionsbestimmung in einem Gebiet mit '
        'schwachem Signal langsam oder instabil ist.',
  ),
  HelpSection(
    title: 'Fahrzeugsymbol',
    body:
        'Unter Einstellungen > Fahrzeugsymbol können Sie den '
        '"Hier bin ich"-Marker auf der Karte statt des klassischen Punkts '
        'durch ein Motorrad- oder Autosymbol ersetzen, jeweils in 5 '
        'verschiedenen Größen-/Farbvarianten. Farbe und Größe der '
        'Statistik-Symbole lassen sich separat unter Einstellungen > '
        '"Statistik-Symbolerscheinungsbild" anpassen. Ihre Wahl bleibt '
        'bestehen, bis Sie sie erneut ändern.',
  ),
  HelpSection(
    title: 'Android Auto',
    body:
        'Eine auf dem Telefon gestartete Aufzeichnung kann auch über den '
        'Bildschirm des Autos angezeigt und gesteuert werden: '
        'Geschwindigkeit, Dauer und Distanz werden dort ebenfalls '
        'angezeigt, Pausieren/Fortsetzen und Beenden funktionieren auch '
        '(aus Gründen der Fahrsicherheit kann am Autobildschirm kein Name '
        'eingegeben werden, die Aufzeichnung wird automatisch benannt '
        'gespeichert). Die Telefon-App muss dafür nur einmal geöffnet '
        'worden sein. CarPlay wird noch nicht unterstützt - dafür ist '
        'eine besondere Berechtigung von Apple nötig.',
  ),
  HelpSection(
    title: 'Exportieren',
    body:
        'Das Teilen-Symbol auf dem Kartenbildschirm exportiert die '
        'geöffnete Route als GPX, KML oder KMZ - wählen Sie einen '
        'Dateinamen (der Name der Route wird standardmäßig '
        'vorgeschlagen) und teilen Sie sie mit einer anderen App oder '
        'Person. Bei zusammengeführten Routen (mit automatischem Namen '
        '"A + B") möchten Sie meist einen anderen Namen vergeben.',
  ),
  HelpSection(
    title: 'App-Updates',
    body:
        'Unter Android fragt die App beim Start nach einem Update - ein '
        'Tipp auf "Aktualisieren" reicht. Alles Weitere läuft im '
        'Hintergrund, ohne die App zu sperren: Der Download-Fortschritt '
        'wird in einem Banner unten angezeigt, danach öffnet sich '
        'automatisch das Installationsprogramm, und der alte App-Prozess '
        'beendet sich selbst - ein Zurückwischen führt zur neuen Version, '
        'nicht zur veralteten. Schließen Sie den Dialog, bleibt oben ein '
        'Banner mit derselben Schaltfläche, sobald Sie bereit sind. Die '
        'Web-Version lädt bei jedem Besuch die neueste Version.',
  ),
  HelpSection(
    title: 'Sprache ändern',
    body:
        'Im Bereich Sprache der Einstellungen können Sie zwischen '
        'Türkisch, Englisch und Deutsch wechseln. Ihre Wahl wird '
        'gespeichert und beim nächsten Öffnen der App beibehalten.',
  ),
];
