/// Full version history, shown in Settings > About.
///
/// Keep this in sync with [kAppBuildLabel]/[kAppBuildNoteTr]/[kAppBuildNoteEn]
/// in build_info.dart: every time those are bumped for a push, add a new
/// entry here too (newest first). Notes are bilingual (Turkish + English);
/// German falls back to English.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.noteTr,
    required this.noteEn,
  });

  final String version;

  /// ISO date (yyyy-MM-dd) this version was pushed.
  final String date;
  final String noteTr;
  final String noteEn;

  /// Turkish when [languageCode] is `tr`, otherwise English (including `de`).
  String noteFor(String languageCode) =>
      languageCode == 'tr' ? noteTr : noteEn;
}

const kChangelog = <ChangelogEntry>[
  ChangelogEntry(
    version: 'v1.4.130 beta',
    date: '2026-11-04',
    noteTr:
        'Dil İngilizceyken sürüm geçmişi, yenilikler penceresi ve kalan sabit '
        'Türkçe metinler (Android Auto, kayıt bildirimi, analiz ilerleme) '
        'İngilizce.',
    noteEn:
        'With English selected, version history, the what’s-new dialog, and '
        'leftover hardcoded copy (Android Auto, the recording notification, '
        'analysis progress) are now English too.',
  ),
  ChangelogEntry(
    version: 'v1.4.129 beta',
    date: '2026-11-04',
    noteTr:
        'Evde akşamdan sabaha kayıt ~2.4 km ve 7 saat “aktif” yazıyordu: 25 m '
        'eşiği gece GPS yumağını tek tek kabul edip duraklatmayı açıyordu. '
        'Artık durulan noktaya kilit: üst üste 3 fix her biri ≥80 m '
        'uzaklaşmadan iz büyümez, otomatik duraklama kalkmaz.',
    noteEn:
        'An overnight indoor recording used to log ~2.4 km and 7 hours '
        '“active”: the 25 m hop rule accepted each GPS scribble and cleared '
        'auto-pause. The parked spot is now locked — the track does not grow '
        'and pause does not lift until three fixes in a row are each ≥80 m '
        'away.',
  ),
  ChangelogEntry(
    version: 'v1.4.128 beta',
    date: '2026-11-04',
    noteTr:
        'Evde dururken v1.4.127 hâlâ ~100 m ve 10 km/s bırakabiliyordu: '
        'telefon doğruluğu 8 m deyince 12 m’lik iç mekân zıplaması gerçek '
        'sanılıyordu. Artık hop en az 25 m ve 2× bildirilen doğruluk '
        'dışındaysa hareket sayılır; otomatik duraklama daha erken tutar.',
    noteEn:
        'While sitting still, v1.4.127 could still write ~100 m and 10 km/h: '
        'a phone that reported 8 m accuracy treated a 12 m indoor hop as '
        'real. Movement now counts only if the hop is at least 25 m and '
        'outside 2× the reported accuracy, so auto-pause holds sooner.',
  ),
  ChangelogEntry(
    version: 'v1.4.127 beta',
    date: '2026-11-04',
    noteTr:
        'Evde dururken GPS sapması (ör. 6 km, 72 km/s, irtifa inip çıkması) '
        'artık mesafe/hız yazmaz. İç mekân 20–40 m zıplamaları hem izi '
        'şişiriyor hem otomatik duraklatmayı kaldırıyordu; bildirilen '
        'doğruluk çemberinin içindeki hop hareket sayılmaz, duraklama ancak '
        'çemberin belirgin dışına çıkınca açılır. Kaydetmede native iz de '
        'aynı süzgeçten geçer.',
    noteEn:
        'Indoor GPS wander (e.g. 6 km, 72 km/h, altitude bouncing) no longer '
        'writes distance or speed. 20–40 m indoor hops both bloated the track '
        'and cleared auto-pause; hops inside the reported accuracy circle do '
        'not count as movement, and pause lifts only after a clear exit. The '
        'native save path uses the same filter.',
  ),
  ChangelogEntry(
    version: 'v1.4.126 beta',
    date: '2026-10-13',
    noteTr:
        'Çok günlük kayıtlarda her yerel gün, Analiz "Günlük" ile aynı '
        'sınırlarla tek GPX olarak yedeklenebiliyor '
        '(RideAtlas_yyyy-MM-dd.gpx) - dosyada yalnızca o günün noktaları. '
        'Ayarlar > Günlük Drive yedeği ile Google Drive klasörü seçilir '
        '(Android SAF); gece yarısı geçen gün ve kayıt sırasında kaydetme '
        'tetikler.',
    noteEn:
        'On multi-day recordings each local day can be backed up as its own '
        'GPX (RideAtlas_yyyy-MM-dd.gpx) using the same day boundaries as '
        'Analysis → Daily — only that day\'s points. Settings → Daily Drive '
        'backup picks a Google Drive folder (Android SAF); midnight and '
        'Save-during-recording both write the completed day.',
  ),
  ChangelogEntry(
    version: 'v1.4.125 beta',
    date: '2026-09-29',
    noteTr:
        'Ayarlar\'a "Güncellemeleri kontrol et" satırı eklendi: çalışan sürümü '
        'gösterir, GitHub\'daki android-latest ile karşılaştırır; güncelseniz '
        'söyler, yeni APK varsa aynı Güncelle / indirme akışını başlatır. '
        'Web\'de service worker yoklaması yapıp alttaki mevcut Güncelle '
        'banner\'ını kullanır (ikinci bir web güncelleme UI\'ı yok).',
    noteEn:
        'Settings now has “Check for updates”: it shows the running version, '
        'compares it to GitHub android-latest, says if you are current, and '
        'starts the same Update / download flow when a new APK exists. On web '
        'it probes the service worker and uses the existing bottom Update '
        'banner (no second web update UI).',
  ),
  ChangelogEntry(
    version: 'v1.4.124 beta',
    date: '2026-09-29',
    noteTr:
        'Kayıt haritasında canlı kırmızı ize dokunarak not ve/veya fotoğraf '
        'eklenebiliyor; kaydetince GPX waypoint ve rota fotoğrafı olarak '
        'saklanıyor. Kapalı alanda GPS\'in telefon dururken gösterdiği sahte '
        '2–5 km/s sürüklenme, yer değiştirmeye göre sınırlandırılıyor — hız '
        'HUD\'da ~0 görünür ve otomatik duraklama yine devreye girer. Mevcut '
        'sıçrama / imkânsız hız filtreleri aynı kaldı.',
    noteEn:
        'On the recording map you can tap the live red track to add a note '
        'and/or photo; they are stored as a GPX waypoint and route photo on '
        'save. Indoor GPS fake 2–5 km/h crawl while the phone is still is '
        'capped by actual movement — the HUD shows ~0 and auto-pause still '
        'engages. Existing jump / impossible-speed filters are unchanged.',
  ),
  ChangelogEntry(
    version: 'v1.4.123 beta',
    date: '2026-09-23',
    noteTr:
        'Kayıt haritasındaki hız rakamı artık tek satırda ortalanıyor: hane '
        'artınca (ör. 97 → 108) gerekirse küçülüyor, rakamlar alt alta '
        'kırılmıyor. Üst sıradaki gereksiz Spacer kaldırıldı - hız kutusu '
        'sola sıkışıp "9 / 7" diye iki satıra bölünüyordu.',
    noteEn:
        'The recording-map speed figure stays on one centered line: it '
        'shrinks when digits grow (e.g. 97 → 108) instead of wrapping. A '
        'leftover Spacer in the top row was removed — it used to squeeze the '
        'speed box so “97” split onto two lines.',
  ),
  ChangelogEntry(
    version: 'v1.4.122 beta',
    date: '2026-09-11',
    noteTr:
        'Uygulama sürekli açıksa (ör. gece boyu kayıt) her gün yerel saat '
        '12:00\'de güncelleme kontrolü yapılıyor; yeni sürüm varsa sessizce '
        'indirmeye başlıyor - yalnızca açılışta bakmakla kalmıyor.',
    noteEn:
        'If the app stays open (e.g. overnight recording), it checks for '
        'updates every day at local noon and starts a silent download when a '
        'new version exists — not only on launch.',
  ),
  ChangelogEntry(
    version: 'v1.4.121 beta',
    date: '2026-09-11',
    noteTr:
        'Rota seçim ekranında Göster/Gizle yerine Tamam/Vazgeç var; seçimi '
        'boş bırakıp Tamam deyince haritadaki rotalar kalkıyor. İşaretlenen '
        'rotalar için çöp kutusu çıkıyor - seçililer kalıcı silinebiliyor.',
    noteEn:
        'The route picker uses OK/Cancel instead of Show/Hide; confirming '
        'with nothing selected clears routes from the map. A trash control '
        'appears for checked routes so you can delete the selection '
        'permanently.',
  ),
  ChangelogEntry(
    version: 'v1.4.120 beta',
    date: '2026-09-09',
    noteTr:
        'Seçili rotayı silmek artık rota detay haritasında (⋮ menü) ve ana '
        'ekran / kayıt haritasında rotaya dokununca çıkan etiketin altındaki '
        'Sil tuşuyla mümkün - yalnızca rota listesinden silmek zorunda '
        'kalınmıyor.',
    noteEn:
        'Deleting the selected route is now possible from the route-detail '
        'map (⋮ menu) and from the Delete button under the name chip when you '
        'tap a route on the home or recording map — you no longer have to go '
        'through the route list.',
  ),
  ChangelogEntry(
    version: 'v1.4.119 beta',
    date: '2026-09-07',
    noteTr:
        'Otomatik güncelleme kontrolü artık tamamen sessiz: ana ekran '
        'açılışında yeni bir sürüm bulunursa "güncelle ister misin?" diye '
        'sormadan direkt indirmeye başlıyor (ilerleme durumu yine banner\'da '
        'görünüyor). Kurulum anında Android\'in kendi kurulum onay ekranı yine '
        'de çıkar - bunu hiçbir uygulama atlayamaz, tek "onay" adımı artık '
        'bu.',
    noteEn:
        'Automatic update checks are fully silent: if a new version is found '
        'when the home screen opens, download starts without asking “do you '
        'want to update?” (progress still shows on the banner). Android still '
        'shows its own install confirmation — no app can skip that; it is now '
        'the only confirm step.',
  ),
  ChangelogEntry(
    version: 'v1.4.118 beta',
    date: '2026-09-07',
    noteTr:
        'Ana ekranın "Rota seç..." penceresindeki 10/24 rota sınırı '
        'kaldırıldı - Home\'un amacı zaten rotaları yükleyip görmek, sınırlama '
        'orada mantıksızdı. Aynı sınır, aynı gerekçeyle route list\'ten çoklu '
        'rota haritasına (multi_route_map_screen) girerken de kaldırıldı. '
        'Kayıt ekranındaki overlay seçimi (canlı GPS kaydı sırasında, '
        'performans için) eskisi gibi 10/24 sınırlı kaldı - harita zaten '
        'Android\'de ~20+ rotada donma riski taşıyor olduğu için orada '
        'kısıtlama hâlâ gerekli.',
    noteEn:
        'The 10/24 route cap on the home “Select route…” sheet is gone — Home '
        'is meant to load and show routes. The same cap is removed when '
        'opening the multi-route map from the list. The recording overlay '
        'picker stays capped at 10/24 for performance — the live map can '
        'freeze around 20+ tracks on Android.',
  ),
  ChangelogEntry(
    version: 'v1.4.117 beta',
    date: '2026-09-07',
    noteTr:
        'Canlı testte bulunan bir dizi küçük ama gerçek sorun düzeltildi. (1) '
        'Kayıt ekranının rota menüsü ("Tümünü göster"/"Tümünü gizle" '
        'kaldırıldı) artık ana ekranınkiyle tutarlı: sadece "Rota seç..." ve '
        '"İçe aktar...". (2) Veri sayfasına da (kayıt sürerken bile) geri '
        'tuşu eklendi - PopScope zaten izin verdiği için kayıt sürerken önce '
        'Harita sayfasına geçiyor, oradan bir daha basınca Ana ekrana '
        'çıkıyor. (3) Ana ekranda tek rota seçmek (Rota seç... ile veya tek '
        'dosya içe aktararak) artık o rotayı da overlay\'e ekliyor - önceden '
        'sadece detay sayfasına gidip overlay\'i hiç dokunmuyordu; şimdi geri '
        'dönüldüğünde o tek rota haritada görünüyor ve "Rota seç..." tekrar '
        'açıldığında işaretli geliyor, çoklu seçimde olduğu gibi. (4) Rota '
        'detay ekranındaki (tek rota haritası) "rota değiştir" listesi '
        'düğmesi kaldırıldı - artık gereksiz, rota seçimi tamamen ana '
        'ekrandan yönetiliyor; o düğmenin altındaki anormal-nokta-düzenleme '
        'özelliği kaybolmadı, sağ üstteki yeni bir menüye taşındı. (5) Rota '
        'seçim penceresine sağ üstte bir sıralama düğmesi eklendi: tarihe '
        '(kayıt tarihi), isme, veya uzunluğa göre. (6) Kayıt ekranındaki hız '
        'göstergesi artık ekranın ortasında; hane sayısı (1/2/3 haneli hız) '
        'arttıkça sağdan sola tek yönlü büyümek yerine iki yandan simetrik '
        'genişliyor.',
    noteEn:
        'Live-test fixes. (1) The recording-screen route menu now matches '
        'Home: only “Select route…” and “Import…”. (2) The Data page also has '
        'a back button — while recording it first returns to Map, then Home. '
        '(3) Picking a single route (or importing one file) now also adds it '
        'as a home overlay, so it is still on the map when you come back. (4) '
        'The route-detail “switch route” list button is gone; anomaly editing '
        'moved to a new top-right menu. (5) The route picker has a sort '
        'button: date, name, or length. (6) Recording-screen speed is '
        'centered and grows symmetrically as digits are added.',
  ),
  ChangelogEntry(
    version: 'v1.4.116 beta',
    date: '2026-09-07',
    noteTr:
        'İki eksiklik canlı testte bulundu ve düzeltildi. (1) Kayıt '
        'ekranından ana harita ekranına dönecek görünür bir tuş yoktu - '
        'v1.4.112\'de üstteki geri oku kaldırılıp sistem geri tuşu/hareketine '
        'bırakılmıştı, ama iOS web\'de bunun güvenilir bir karşılığı yok; '
        'kayıt sürerken kullanıcının Ana ekrana dönecek hiçbir yolu '
        'kalmamıştı. Harita sayfasının sol üstüne (hem boşta hem kayıt '
        'sırasında) bir geri oku eklendi - PopScope\'un zaten izin verdiği tam '
        'olarak aynı davranışı tetikliyor, kayıt arka planda devam ediyor. '
        '(2) Ana ekranda birden fazla iz overlay olarak gösterildiğinde '
        '(v1.4.115), o izlere yeniden sığdıracak bir tuş yoktu - haritada '
        'uzaklaşıp/yakınlaştıktan sonra manuel olarak eski konuma dönmek '
        'gerekiyordu. Sağ alttaki zoom tuşlarının arasına, izler '
        'gösteriliyorken çıkan bir "sığdır" tuşu eklendi.',
    noteEn:
        'Two live-test gaps. (1) After v1.4.112 removed the top back arrow, '
        'iOS web had no reliable way back to Home while recording. A back '
        'arrow is on the map page (idle and recording) and triggers the same '
        'PopScope path — recording continues. (2) With several overlay tracks '
        'on Home there was no refit control; a fit button now sits among the '
        'zoom buttons when tracks are shown.',
  ),
  ChangelogEntry(
    version: 'v1.4.115 beta',
    date: '2026-09-07',
    noteTr:
        'Ana ekranın "Rota seç..." akışı yeniden kurgulandı. Önceki sürümde '
        '(v1.4.113) birden fazla rota seçmek ayrı bir ekrana '
        '(MultiRouteMapScreen) götürüyordu; sistem geri tuşuna basınca o '
        'ekran kapanıyor, izleri tekrar görmek için "Rota seç..." penceresini '
        'yeniden açıp onaylamak gerekiyordu - kullanıcı testi sırasında bunun '
        '"hiç kapanmamış gibi devam etme" beklentisini karşılamadığı, ayrıca '
        'gerçek bir hata barındırdığı ortaya çıktı: gösterilen tüm izlerin '
        'işaretini kaldırıp onaylayınca (24 rotayı seçip "Hepsi" ile hepsini '
        'kaldırma senaryosu) bu boş seçim hiç hafızaya yazılmıyordu - ekran '
        'tekrar açıldığında eski, kaldırılmış seçim geri geliyordu, sanki hiç '
        'temizlenmemiş gibi. Şimdi: kayıt ekranındaki referans-iz mantığıyla '
        'aynı yaklaşım - seçilen izler doğrudan ana ekranın kendi haritasının '
        'üzerine çiziliyor, ayrı ekrana hiç gidilmiyor; bu seçim (boş dahil) '
        'her zaman doğru şekilde hafızaya yazılıp uygulama yeniden '
        'açıldığında geri yükleniyor. Tek rota seçilirse (Rota seç... ile '
        'veya tek dosya içe aktararak) otomatik olarak o rotanın tam detay '
        'ekranına (gün bazlı analiz, yükseklik, hava durumu, tam çözünürlük) '
        'gidiliyor - MultiRouteMapScreen\'in paylaşılan/düşürülmüş çözünürlük '
        'bütçesine hiç girmiyor. Çoklu izler gösterilirken haritada birine '
        'dokununca ismi ve yanında bir "Detaylı analiz" butonu çıkıyor, ona '
        'basınca da aynı tam detay ekranı açılıyor. Ayrıca rota seçim '
        'penceresinin "Göster" butonu artık hiçbir şey seçili değilken '
        'pasifleşmek yerine "Gizle" yazıp etkin kalıyor - bilerek boş '
        'bırakmayı gerçek bir seçenek haline getiriyor.',
    noteEn:
        'Home “Select route…” no longer opens a separate MultiRouteMapScreen. '
        'Selected tracks draw on the home map itself and the selection '
        '(including empty) is persisted. A single route still opens the full '
        'detail screen. Tapping a track among several shows its name and '
        '“Detailed analysis”. The picker’s Show button stays enabled as Hide '
        'when nothing is selected, so clearing the map is a real choice.',
  ),
  ChangelogEntry(
    version: 'v1.4.114 beta',
    date: '2026-09-07',
    noteTr:
        'Rota seçim penceresi baştan tasarlandı. Eskiden kutu içinde sade bir '
        '"Hepsi + checkbox listesi" olan AlertDialog, üç ayrı yerde (kayıt '
        'ekranının referans iz overlay\'i, çoklu-rota haritasının "N rota" '
        'pilinden açılan yeniden seçim, ana ekranın "Rota seç...") de aynı '
        '"amatör" görünümdeydi. Şimdi alttan açılan, yuvarlak köşeli bir '
        'panel: "Hepsi" satırı ve kaç rotanın seçili olduğu ("2/5" gibi) '
        'listenin üstünde sabit duruyor (artık kaydırılıp gözden kaçmıyor), '
        'her rota haritada çizileceği renkle (çoklu-rota haritasındaki legend '
        'ile aynı renk sırası) önizleniyor, "Göster" butonu seçili sayıyı '
        'gösteriyor ve hiçbir şey seçili değilken pasif oluyor.',
    noteEn:
        'The route picker is a bottom sheet instead of a plain checkbox '
        'dialog. The All row and selected count stay pinned at the top, each '
        'route is previewed in its map color, and Show reports the selected '
        'count and is disabled when none are checked.',
  ),
  ChangelogEntry(
    version: 'v1.4.113 beta',
    date: '2026-09-07',
    noteTr:
        'Ana ekrandaki rota menüsü sadeleştirildi: "Tümünü göster" ve '
        '"Rotalar" listesi menüden kaldırıldı ("Hepsi" zaten "Rota seç..." '
        'penceresinde vardı), sol üstteki rota ikonu yerine düz "Rotalar" '
        'yazısı kondu. Rota yeniden adlandırma/birleştirme/silme ekranı artık '
        'Ayarlar > Rotalar\'dan açılıyor (menüden kaldırıldığı için erişimi '
        'orada kalsın diye taşındı). En büyük değişiklik: izleri gösteren '
        'harita ekranı artık en son hangi izler gösteriliyorduysa onu '
        'hatırlıyor - "Rota seç..." penceresi son seçimi işaretli açılıyor, '
        've aynı seçimle yeniden açıldığında harita da kapanmadan önceki '
        'zoom/konumla devam ediyor (her seferinde yeniden çerçeveleme '
        'yapmıyor). Ayrıca üç ayrı yerde (kayıt ekranı, çoklu-rota haritası, '
        'ana ekran) neredeyse aynı olan "Hepsi + rota listesi" seçim '
        'penceresi tek bir ortak bileşene indirildi.',
    noteEn:
        'Home route menu simplified: “Show all” and the Routes list left the '
        'menu (All is already in “Select route…”); the icon is now a “Routes” '
        'label. Rename/merge/delete moved to Settings → Routes. The map '
        'remembers the last shown tracks, restores the picker checks, and '
        'keeps zoom/position instead of re-fitting every time. The three '
        'nearly identical All+list pickers are now one shared widget.',
  ),
  ChangelogEntry(
    version: 'v1.4.112 beta',
    date: '2026-09-06',
    noteTr:
        'GPX içe aktarmadaki "sessizce hiçbir şey olmuyor" hatasının kök '
        'nedeni bulundu: web dosya seçicisinde tarayıcı, gerçekten bir dosya '
        'seçilmiş olsa bile "cancel" DOM olayını "change" olayından önce '
        'tetikleyebiliyordu - önceki düzeltmedeki sabit 400ms gecikme bile bu '
        'farkı her zaman kapatamıyordu, canlı testte 4/4 denemede içe aktarma '
        'hâlâ başarısız oluyordu. Şimdi sabit bir gecikme yerine, gerçek '
        '"change" olayı gelene ya da okuma başlayana kadar (en fazla ~2 '
        'saniye) tekrar tekrar kontrol ediliyor; canlı testte art arda 4/4 '
        'çalıştı. Ayrıca kayıt ekranının gezinme modeli sadeleştirildi: artık '
        'yalnızca iki sayfa var (Harita, Veri), üstteki geri oku tuşu tamamen '
        'kaldırıldı (sistem geri tuşu/hareketi zaten aynı işi görüyor - '
        'boştayken ekrandan çıkar, kayıt sırasında Veri sayfasındayken önce '
        'Haritaya döner). Yeni bir kayıt başlatıldığında (henüz kayıt yokken) '
        'her zaman Veri sayfasında açılıyor; devam eden bir kayıt yeniden '
        'açıldığında ise en son hangi sayfada kalındıysa (Harita ya da Veri) '
        'orada açılıyor. Kayıt ekranında gösterilen referans izler de artık '
        'hatırlanıyor: seçilen izler bir sonraki kayıt ekranı açılışında '
        'otomatik olarak yeniden gösteriliyor.',
    noteEn:
        'Silent GPX import on web: the browser could fire cancel before '
        'change even after a 400 ms delay. The picker now waits (up to ~2 s) '
        'until a real change or a read starts — 4/4 in live tests. Recording '
        'navigation is two pages (Map, Data); the top back arrow is gone '
        '(system back does the same). A new recording opens on Data; a '
        'resumed one reopens the last page. Reference tracks on the recording '
        'map are remembered.',
  ),
  ChangelogEntry(
    version: 'v1.4.111 beta',
    date: '2026-09-06',
    noteTr:
        'Kayıt / konum beyaz ekranının gerçek kök nedeni bulundu. v1.4.109 ve '
        'v1.4.110 harita karolarının yüklenme zamanlamasını düzeltmeye '
        'çalışmıştı ama bu yanlış teşhisti - ekran hâlâ bomboş kalıyordu. '
        'Uygulama yerel olarak derlenip gerçek bir tarayıcıda adım adım test '
        'edilerek asıl neden bulundu: kayıt ekranının Stack\'i içindeki '
        '"kesintiye uğramış kayıt devam ediyor" bildirimini çizen '
        '_buildResumedFlash metodu, bildirim gösterilmeyecekse (kayıtların '
        'büyük çoğunluğunda böyle) konumlandırılmamış (Positioned olmayan) '
        'boş bir widget döndürüyordu. Stack\'in diğer tüm elemanları '
        'Positioned iken aralarına Positioned olmayan bir eleman girince '
        'Flutter o Stack\'in TAMAMINI (harita, tüm tuşlar, her şey) çizmeyi '
        'bırakıyordu - sadece o küçük bildirim widget\'ı değil. Düzeltme tek '
        'satır: boş durumda da Positioned.fill ile sarmalanmış bir widget '
        'döndürülüyor artık.',
    noteEn:
        'The recording / location white screen was not a tile-timing bug. '
        '_buildResumedFlash returned a non-Positioned empty widget when the '
        'resume toast was hidden; Flutter then skipped painting the entire '
        'Stack (map and all buttons). Empty state now returns a '
        'Positioned.fill widget.',
  ),
  ChangelogEntry(
    version: 'v1.4.110 beta',
    date: '2026-09-06',
    noteTr:
        'v1.4.109 derlemesi kırılmıştı: kayıt ekranında _tileLayerEpoch alanı '
        'eksikti, web/APK çıkmadı. Alan geri eklendi; kayıt/konum beyaz ekran '
        'düzeltmesi (GPS merkezi, onMapReady kick, TileLayer remount) artık '
        'gerçekten dağıtılıyor.',
    noteEn:
        'v1.4.109 did not compile: RecordScreen was missing _tileLayerEpoch, '
        'so web/APK never shipped. The field is back; the GPS-center / '
        'onMapReady / TileLayer remount fix is actually released.',
  ),
  ChangelogEntry(
    version: 'v1.4.109 beta',
    date: '2026-09-06',
    noteTr:
        'Ana ekran kayıt / konum (ve kayıt sırasında konuma git) beyaz ekran: '
        'RecordScreen’e son GPS merkezi aktarılıyor; onMapReady + geniş zoom '
        '+ soft karo zemini; gecikmeli TileLayer remount + kick. Konuma git / '
        'Data→Harita geçişinde de aynı güçlendirme.',
    noteEn:
        'Home recording / location (and recenter while recording) white '
        'screen: RecordScreen now receives the last GPS center; onMapReady + '
        'wide zoom + a soft tile floor; delayed TileLayer remount + kick. '
        'Recenter and Data→Map use the same strengthening.',
  ),
  ChangelogEntry(
    version: 'v1.4.108 beta',
    date: '2026-09-06',
    noteTr:
        'Android’de ~20 izle “tüm izleri göster” kilitlenmesi: harita için '
        'toplam köşe bütçesi (~6k), iz başına daha agresif sadeleştirme, '
        'paralel parse 4→2, progress setState throttle, çok izde foto pin '
        'yok, polyline daha ince. Soft/hard cap 10/24.',
    noteEn:
        'Android freeze showing ~20 tracks: a ~6k vertex budget for the map, '
        'more aggressive per-track simplify, parallel parse 4→2, throttled '
        'progress setState, no photo pins on many tracks, thinner polylines. '
        'Soft/hard caps 10/24.',
  ),
  ChangelogEntry(
    version: 'v1.4.105 beta',
    date: '2026-09-06',
    noteTr:
        'Ana ekran iz menüsünden GPX/KML/KMZ içe aktarma hataları (okunamayan '
        'dosya, desteklenmeyen tür, yinelenen rota, parse hatası) sessizce '
        'yutuluyordu — snackbar + mevcut rotayı açma eklendi. iPhone kayıt '
        'ekranı boş beyaz kalma: harita karo kick (ana haritadaki gibi).',
    noteEn:
        'GPX/KML/KMZ import errors from the home track menu (unreadable file, '
        'unsupported type, duplicate, parse error) were swallowed — snackbar '
        '+ opening the existing route added. iPhone recording screen staying '
        'white: map tile kick like the home map.',
  ),
  ChangelogEntry(
    version: 'v1.4.104 beta',
    date: '2026-09-06',
    noteTr:
        'v1.4.103 derlemesi kırılmıştı: kayıt ekranında track_io importu '
        'eksikti, web/APK çıkmadı. Import geri eklendi; tüm izleri göster '
        'hızlandırması (paralel yükleme, bellek önbelleği, tek seferde çizim) '
        'artık gerçekten dağıtılıyor.',
    noteEn:
        'v1.4.103 did not compile: RecordScreen was missing a track_io '
        'import. Import restored; show-all-tracks speedups (parallel load, '
        'memory cache, one-shot draw) now actually ship.',
  ),
  ChangelogEntry(
    version: 'v1.4.103 beta',
    date: '2026-09-06',
    noteTr:
        'Tüm izleri göster artık önce belleğe alıp paralel parse ediyor, '
        'hazır olunca tek seferde çiziyor; sadeleştirilmiş geometri '
        'önbellekte kalıyor böylece ikinci açılış neredeyse anında. Kayıt '
        'ekranı overlay izleri de aynı hızlı yolu kullanıyor.',
    noteEn:
        'Show all tracks now parses in parallel into memory and draws once; '
        'simplified geometry stays cached so the second open is nearly '
        'instant. Recording overlay tracks use the same fast path.',
  ),
  ChangelogEntry(
    version: 'v1.4.102 beta',
    date: '2026-09-05',
    noteTr:
        'Tüm izleri göster kilitlemesi giderildi: çok izde uyarı/sert sınır, '
        'rota başına daha agresif nokta sadeleştirme, gösterimde ilerleyici '
        'çizim kaldırıldı, harita foto pinleri artık tam görüntü yerine hafif '
        'ikon, iz ismi için dokunma testi örnekleniyor. Kayıt overlay '
        'ekranında da aynı sadeleştirme uygulanıyor.',
    noteEn:
        'Show-all-tracks freeze: warn/hard cap on many tracks, more '
        'aggressive per-route simplify, no progressive draw, photo pins as '
        'light icons, sampled hit-testing for names. Same simplify on the '
        'recording overlay.',
  ),
  ChangelogEntry(
    version: 'v1.4.101 beta',
    date: '2026-09-05',
    noteTr:
        'Kayıt ekranı son Veri/Harita tercihini hatırlıyor; kesilip süren '
        'kayıtta kısa ortada "sürdürülüyor" bildirimi. Ana harita sol üst iz '
        'menüsü (tümünü göster / seç / içe aktar / rota listesi). Kayıt '
        'bitince yalnızca GPS konumlu galeri medyası sunuluyor (konumsuz '
        'yok); fotoğraf iz üzerinde nokta. Çoklu iz / kayıt haritasında ize '
        'dokununca isim balonu açılıp tekrar dokununca kapanıyor.',
    noteEn:
        'Recording screen remembers the last Data/Map page; a short “resumed” '
        'flash after an interrupted session. Home map has a top-left track '
        'menu (show all / pick / import / list). After save, only GPS-tagged '
        'gallery media are offered; photos mark the track. Tapping a track on '
        'multi-track / recording maps toggles a name bubble.',
  ),
  ChangelogEntry(
    version: 'v1.4.100 beta',
    date: '2026-09-05',
    noteTr:
        'Kayıt sırasında geri tuşu kaldırıldı: sol üst yalnızca iz yönetimi '
        '(Tümünü göster / Tümünü gizle / Rota seç... / İçe aktar...) — hem '
        'veri hem harita sayfasında aynı menü. Veri ↔ Harita dönüşümü sadece '
        'sol alttaki tuşla; geri tuşuyla ikinci bir harita yolu yok. Kayıt '
        'başlamadan (idle) haritada geri hâlâ var. Sistem geri: verideyken '
        'haritaya, haritadayken ekrandan çıkış (kayıt arka planda sürer).',
    noteEn:
        'While recording, the back button is gone: top-left is only track '
        'management (Show all / Hide all / Select route… / Import…) on both '
        'Data and Map. Data ↔ Map is only the bottom-left button. Idle map '
        'still has back. System back: Data→Map, Map leaves the screen '
        '(recording continues).',
  ),
  ChangelogEntry(
    version: 'v1.4.99 beta',
    date: '2026-09-05',
    noteTr:
        'Kayıt veri ekranındaki geri tuşu (ve Android sistem geri) artık '
        'kayıt ekranından çıkmak yerine doğrudan haritaya geçiyor - '
        'haritadaki geri tuşu hâlâ ekrandan ayrılmayı sağlıyor (kayıt arka '
        'planda devam eder). Sol alttaki Veri ↔ Haritalar geçişi ve harita '
        'sol üstündeki rota menüsü (Tümünü göster / Tümünü gizle / Rota '
        'seç... / İçe aktar...) v1.4.98\'deki gibi duruyor; alttan açılan '
        'panel yok.',
    noteEn:
        'Back on the recording Data page (and Android system back) now goes '
        'to the map instead of leaving; the map back button still leaves '
        '(recording continues). Bottom-left Data ↔ Maps and the top-left '
        'route menu stay as in v1.4.98; no bottom sheet.',
  ),
  ChangelogEntry(
    version: 'v1.4.98 beta',
    date: '2026-09-05',
    noteTr:
        'v1.4.97\'deki tek-ekran + alttan açılan panel denemesi geri alındı: '
        'kullanıcı canlıda test edince paneli beğenmedi ve önceki iki tam '
        'sayfalı (Veri / Harita, sol alttaki tuşla geçişli) yapının aynen '
        'kalmasını istedi. Sol üstteki rota menüsü (v1.4.97 ile gelen Tümünü '
        'göster / Tümünü gizle / Rota seç... dropdown\'ı) korundu ve '
        'genişletildi: artık aynı menüden "İçe aktar..." ile kayıt ekranından '
        'hiç ayrılmadan yeni bir GPX/KML/KMZ dosyası seçilip hem İzler '
        'listesine kalıcı olarak eklenebiliyor hem de haritada referans rota '
        'olarak gösterilebiliyor.',
    noteEn:
        'The v1.4.97 single-screen + bottom sheet was reverted after live '
        'testing — the two full pages (Data / Map, bottom-left toggle) stay. '
        'The top-left route menu is kept and extended: “Import…” adds a '
        'GPX/KML/KMZ to the library and as a reference track without leaving '
        'recording.',
  ),
  ChangelogEntry(
    version: 'v1.4.97 beta',
    date: '2026-09-05',
    noteTr:
        'v1.4.94\'teki düzenleme yetersiz kalmıştı: kullanıcı hâlâ veri ve '
        'harita arasında iki ayrı sayfa gezinmek zorunda kalıyordu ve sol '
        'üstteki rota tuşu sadece küçük bir onay kutusu diyaloğu açıyordu. Bu '
        'sürümde kayıt ekranı gerçekten tek ekrana indirildi: harita artık '
        'kalıcı taban katman, üzerinde de yukarı/aşağı sürüklenebilen bir '
        'veri paneli (DraggableScrollableSheet) var - kapalıyken sadece '
        'duraklat/kaydet/sıfırla tuşları görünüyor, yukarı çekilince süre, '
        'hız ve tüm özelleştirilebilir istatistik kartları geliyor. Sol '
        'üstteki rota tuşu da referans uygulamadaki gibi gerçek bir açılır '
        'menüye (PopupMenuButton) dönüştürüldü: Tümünü göster / Tümünü gizle '
        '/ Rota seç....',
    noteEn:
        'Recording became one screen: the map is the permanent base with a '
        'draggable data sheet (closed: pause/save/reset; pulled up: time, '
        'speed, stat cards). The top-left route button is a real menu: Show '
        'all / Hide all / Select route….',
  ),
  ChangelogEntry(
    version: 'v1.4.96 beta',
    date: '2026-09-05',
    noteTr:
        'v1.4.93\'ten sonra kullanıcı iPhone/Safari\'de artık GPX dosyasını '
        'seçebildiğini ama rotanın eklenmediğini bildirdi. Kök sebep bir '
        'yarış durumuydu: web dosya seçicisi hem "change" olayını hem de '
        '(Safari "cancel" olayını güvenilir vermediği için eklenen) pencere '
        'odaklanma yedeğini dinliyordu; okuma yavaş kaldığında (büyük '
        'dosya/yavaş cihaz) ikisi de aynı dosyayı aynı anda okumaya '
        'çalışabiliyordu, bu da sessizce başarısız olabiliyordu - ve okuma '
        'başarısız olan dosyalar hiç hata göstermeden tamamen atlanıyordu, '
        'sanki hiçbir şey seçilmemiş gibi. Artık bir okuma başladığında yedek '
        'mekanizma aynı dosyaya asla tekrar dokunmuyor, ve okunamayan bir '
        'dosya da "dosya okunamadı" uyarısıyla kullanıcıya bildiriliyor.',
    noteEn:
        'On iPhone/Safari a GPX could be picked but not added. The web picker '
        'listened to both change and a window-focus fallback; a slow read '
        'could start twice and fail silently. Once a read starts the fallback '
        'never retries the same file, and unreadable files show “could not '
        'read the file”.',
  ),
  ChangelogEntry(
    version: 'v1.4.95 beta',
    date: '2026-09-05',
    noteTr:
        'Sürüm geçmişi buraya v1.4.85\'ten bu yana eklenen sürümlerin hepsiyle '
        'güncellendi - her push\'ta bu listenin atlanmaması gerektiği '
        'hatırlatıldı. Ayarlar > Yardım ekranı çok daha detaylandırıldı: '
        'otomatik duraklamanın tam eşikleri, anormal GPS noktalarını '
        'düzenleme ekranı, kesintiye uğrayan kayıtların otomatik '
        'kurtarılması, uydu sayısı göstergesi, konum izinleri/pil '
        'optimizasyonu, çoklu dosya içe aktarma ve rota taslak ikonları gibi '
        'daha önce hiç anlatılmamış özellikler artık yardım metninde yer '
        'alıyor (TR/EN/DE).',
    noteEn:
        'Version history filled in from v1.4.85 onward — this list must be '
        'updated on every push. Settings → Help is much more detailed: '
        'auto-pause thresholds, anomaly editor, interrupted-recording '
        'recovery, satellite count, location/battery permissions, multi-file '
        'import and route sketch icons (TR/EN/DE).',
  ),
  ChangelogEntry(
    version: 'v1.4.94 beta',
    date: '2026-09-05',
    noteTr:
        'Kayıt ekranı düzeni sadeleşti: referans rota seçme tuşu sağ alttaki '
        'ikon yığınından haritanın sol üstüne (geri tuşunun yanına) taşındı - '
        'hangi rotaların gösterildiğini kontrol etmek artık haritanın '
        'üzerinde, referans uygulamalardaki gibi. Veri ↔ Harita geçiş tuşları '
        'artık her iki ekranda da aynı yerde: sol altta - önceden bilgi '
        'ekranında sağ üstte "haritaya git", harita ekranında ayrı olarak sağ '
        'üstte "veriye dön" duruyordu; şimdi ikisi de simetrik tek bir '
        'konumda.',
    noteEn:
        'Recording layout: the reference-route button moved from the '
        'bottom-right stack to top-left next to back. Data ↔ Map toggles sit '
        'in the same bottom-left corner on both pages.',
  ),
  ChangelogEntry(
    version: 'v1.4.93 beta',
    date: '2026-09-05',
    noteTr:
        'GPX içe aktarmama sorununun asıl kökeni netleşti: kullanıcı '
        'uygulamayı iPhone\'da Safari üzerinden web sitesi olarak açıyordu '
        '(native uygulama değil) - Flutter\'ın web dosya seçicisi uzantı '
        'listesini düz bir "accept=.gpx,.kml,.kmz" dizesine çeviriyor, Safari '
        'ise GPX\'i bu şekilde güvenilir eşleştiremiyor (sadece KML geçiyordu '
        '- en baştaki "gpx kabul etmiyor, kml ediyor" şikayetiyle birebir '
        'uyuşuyor). Web için MediaAtlas\'ın kanıtlanmış çözümü uygulandı: '
        'dosya seçici artık elle kurulan bir HTML girişiyle açılıyor, her '
        'uzantı kendi MIME türüyle ve tanımlanamayan dosyalar için bir yedek '
        'türle eşleştiriliyor, resim/video türü hiç yok - böylece Safari '
        'GPX/KML/KMZ\'yi güvenilir şekilde tanıyor ve "Fotoğraf Kitaplığı" '
        'menüsü de çıkmıyor. Android/iOS native ve masaüstü tarafı değişmedi.',
    noteEn:
        'Safari web import: Flutter’s accept=.gpx,.kml,.kmz string did not '
        'match GPX (only KML worked). Web now opens a hand-built HTML input '
        'with MIME types per extension plus a generic fallback — no '
        'image/video types, so Photo Library is not offered. Native '
        'Android/iOS/desktop unchanged.',
  ),
  ChangelogEntry(
    version: 'v1.4.92 beta',
    date: '2026-09-05',
    noteTr:
        '"Tüm izi göster" tuşu artık MediaAtlas\'taki kadar sağlam: harita '
        'döndürülmüşken bile önce kuzeye sıfırlayıp doğru şekilde sığdırıyor '
        '(döndürülmüş görünüme göre sığdırma yanlış çerçeve hesaplayıp rotayı '
        'ekranın sadece bir kısmında bırakabiliyordu), ve sığdırmanın '
        'gerçekten uygulanıp uygulanmadığını haritanın gerçek son konumuna '
        'bakarak doğruluyor - eskiden "reddedildi" ile "kamera zaten '
        'oradaydı" ayrımı yapılamadığından buton bazen hiçbir şey yapmıyormuş '
        'gibi görünüyordu; artık reddedilirse tüm dünyaya sığdırmaya düşüyor.',
    noteEn:
        '“Show whole track” now resets north first when the map is rotated '
        '(fitting a rotated view framed only part of the route) and verifies '
        'the camera actually moved; if the fit is rejected it falls back to a '
        'world fit so the button never looks dead.',
  ),
  ChangelogEntry(
    version: 'v1.4.91 beta',
    date: '2026-09-05',
    noteTr:
        'Bir önceki düzeltme (v1.4.90) dosya seçiciyi tüm platformlarda '
        'serbest bıraktığından iPhone\'da artık gereksiz yere "Fotoğraf '
        'Kitaplığı" / "Fotoğraf ya da Video Çek" seçenekleri de çıkıyordu - '
        'izin verilen dosya türleri resimleri de kapsayacak kadar '
        'genişlediğinde iOS bu kısayolları ekliyor. Artık bu serbest bırakma '
        'sadece Android\'de uygulanıyor; diğer platformlarda eskisi gibi '
        'gpx/kml/kmz uzantılarına kısıtlı seçim var (iOS bunu sistem MIME '
        'kaydına ihtiyaç duymadan doğru çözüyor). Ayrıca içe aktarma artık '
        'tek seferde birden fazla dosya kabul ediyor, hepsini tek seferde '
        'işleyip "X rota içe aktarıldı, Y dosya atlandı" şeklinde bir özet '
        'gösteriyor.',
    noteEn:
        'v1.4.90’s unrestricted picker made iPhone offer Photo Library / Take '
        'Photo. That loosening is Android-only; other platforms stay filtered '
        'to gpx/kml/kmz. Import now accepts several files at once and reports '
        '“X routes imported, Y skipped”.',
  ),
  ChangelogEntry(
    version: 'v1.4.90 beta',
    date: '2026-09-05',
    noteTr:
        'GPX dosyaları içe aktarma ekranında dosya seçicide hiç '
        'görünmüyor/seçilemiyordu, KML/KMZ ise sorunsuzdu. Sebep: Android\'in '
        'dosya seçicisi uzantıya göre filtrelerken cihazın MimeTypeMap\'inde '
        'çoğu zaman "gpx" için bir kayıt olmuyor, sistem bu dosyaları '
        'listeden tamamen gizliyordu. Artık seçim serbest bırakılıp uzantı '
        'kontrolü uygulama tarafında yapılıyor; desteklenmeyen bir dosya '
        'seçilirse kullanıcı dostu bir uyarı gösteriliyor.',
    noteEn:
        'GPX files were invisible in the Android picker (MimeTypeMap often '
        'has no “gpx” entry) while KML/KMZ worked. The picker is unrestricted '
        'and the app checks the extension, with a friendly warning for '
        'unsupported files.',
  ),
  ChangelogEntry(
    version: 'v1.4.89 beta',
    date: '2026-09-05',
    noteTr:
        'Durma sonrası otomatik duraklama artık tek bir hatalı GPS ölçümüyle '
        '(elde tutarken/multipath yüzünden 1-2 km\'lik anlık sıçrama) '
        'bozulmuyor - böyle bir sıçrama artık göz ardı ediliyor. Güncelleme '
        'kurulunca Android yükleyicisi açıldıktan kısa süre sonra eski '
        'uygulama süreci kendini kapatıyor, eskisine geri dönülmüyor. Uzun '
        'kayıtlarda (binlerce nokta) her "tam tarama" GPS-sıçrama kontrolü '
        'kaydın başından itibaren tüm noktaları taradığından kayıt uzadıkça '
        'harita giderek ağırlaşıp kilitleniyordu - tarama artık en fazla son '
        '3000 noktayla sınırlı. İzler listesinde artık her satırın başında o '
        'rotanın küçük bir taslak çizimi var (rota şekli önceden hesaplanıp '
        'saklanıyor, listenin açılış hızı etkilenmiyor), seçim kutucukları da '
        'baştan görünür - ayrı bir "seçim moduna" girmeye gerek yok. Renk '
        'teması pembe-turuncu yerine mavi-beyaz ağırlıklı hale getirildi '
        '(kırmızı "seed" renk Material 3\'te pembemsi tonlar türetiyordu).',
    noteEn:
        'Auto-pause no longer lifts on a single bad GPS jump (1–2 km while '
        'holding the phone). After an update the old process exits once the '
        'Android installer opens. Long recordings no longer full-scan every '
        'GPS-jump check from the start — only the last 3000 points. Route '
        'list rows show a precomputed sketch and always-visible checkboxes. '
        'Theme shifted from pink-orange toward blue-white.',
  ),
  ChangelogEntry(
    version: 'v1.4.88 beta',
    date: '2026-09-05',
    noteTr:
        'Uygulama ikonu bir kez daha sadeleşti: aynı kompozisyon, kalın krem '
        'renkli siluetler ve koyu lacivert dağlarla çok daha yalın/piktogram '
        'tarzı bir görünüm - V2\'den daha yüksek kontrast. Arka plan rengi '
        'yine yeni gökyüzü tonuna göre güncellendi.',
    noteEn:
        'App icon simplified again: same composition, thicker cream '
        'silhouettes and dark navy mountains, higher contrast than V2. '
        'Background color matches the new sky.',
  ),
  ChangelogEntry(
    version: 'v1.4.87 beta',
    date: '2026-09-05',
    noteTr:
        'Uygulama ikonu daha yalın, yüksek kontrastlı bir versiyona geçti: '
        'aynı kompozisyon (arkadan motorcu, kıvrılan yol, gün batımı, hedef '
        'pini) ama küçük boyutlarda (48px ve altı) daha net görünen kalın '
        'çizgili, krem rötuşlu bir stil - önceki yumuşak/gradyanlı versiyon '
        'küçültülünce motorcu koyu bir lekeye dönüşüyordu. Arka plan rengi '
        'yeni gökyüzü tonuna göre güncellendi.',
    noteEn:
        'App icon moved to a high-contrast, thick-line cream style that stays '
        'readable at 48 px and below — the previous soft/gradient rider '
        'collapsed into a dark blob. Background updated to the new sky.',
  ),
  ChangelogEntry(
    version: 'v1.4.86 beta',
    date: '2026-09-05',
    noteTr:
        'Uygulama ikonu değişti: gün batımında arkadan görünen bir motorcu, '
        'kıvrılan dağ yolu ve yolun ilerisinde kırmızı bir hedef pini. Tüm '
        'platformlar (Android, iOS, macOS, web, Windows) için ikon dosyaları '
        'yeniden üretildi; Android\'in adaptif ikonundaki eski logo için '
        'ayarlanmış %16 boşluk kaldırıldı (tam kadraj sahne artık kenara '
        'kadar dolduruyor); arka plan rengi yeni ikonun gökyüzü tonuna göre '
        'güncellendi.',
    noteEn:
        'New app icon: rider from behind at sunset, winding mountain road, '
        'red destination pin. Icons regenerated for Android, iOS, macOS, web, '
        'Windows; Android adaptive safe-zone padding removed so the scene '
        'fills the frame.',
  ),
  ChangelogEntry(
    version: 'v1.4.85 beta',
    date: '2026-09-04',
    noteTr:
        'İz çizgileri virajlı dağ yollarında köşeleri kesip düz bir çizgiye '
        'dönüştürüyordu - harita basitleştirme toleransı 1.5\'ten 0.4\'e '
        'düşürüldü. Ayrıca çok günlük bir turda günlük nokta bütçesi gün '
        'sayısına bölünüyordu, bu da tek bir günü 400 noktaya kadar '
        'sıkıştırıp virajları düzleştirebiliyordu - bu sınırlama kaldırıldı. '
        'Rota detayı ve çoklu rota ekranlarındaki "konumum" ikonu '
        'MediaAtlas\'taki gibi doğru "tüm izi sığdır" ikonu ve ipucu metniyle '
        'değiştirildi (zaten GPS konumuna değil rotaya sığdırıyordu).',
    noteEn:
        'Track lines were cutting corners on winding mountain roads — map '
        'simplify tolerance 1.5 → 0.4. Multi-day tours no longer split the '
        'point budget across days (that could flatten a day to ~400 points). '
        'Route detail and multi-route “my location” icons are now the correct '
        'fit-whole-track icon and tooltip.',
  ),
  ChangelogEntry(
    version: 'v1.4.84 beta',
    date: '2026-09-02',
    noteTr:
        'Android "RideAtlas ile aç": soğuk açılışta dosya yayın akışında '
        'dinleyici yokken düşüyordu — uygulama açılıyor, iz kaydedilmiyordu. '
        'Şimdi önce dinle, sonra al; import izler listesine yazılır, harita '
        'açılır. Haritada çizgi her zaman nokta nokta (eski→yeni) büyür; '
        'büyük GPX sadeleştirilmiş köşelerle animasyonlanır.',
    noteEn:
        'Android “Open with RideAtlas”: a cold start dropped the file because '
        'no listener was registered yet — the app opened, the track was not '
        'saved. Listen first, then receive; import writes the rides list and '
        'opens the map. The line always grows old→new; large GPX files '
        'animate with simplified vertices.',
  ),
  ChangelogEntry(
    version: 'v1.4.83 beta',
    date: '2026-08-30',
    noteTr:
        'Büyük rota haritası (ör. 8 günlük GPX): kaydırma/pinch sırasında on '
        'binlerce nokta her karede boyanıyordu ve kilitleniyordu. Ekranda en '
        'fazla ~8000 köşe çizilir (analiz/kayıt tam kalır); 3000+ noktada '
        'çizgi animasyonu atlanır; dokununca animasyon iptal. flutter_map '
        'sadeleştirme toleransı yükseltildi.',
    noteEn:
        'Large route maps (e.g. 8-day GPX) froze on pan/pinch because tens of '
        'thousands of points painted every frame. At most ~8000 on-screen '
        'vertices (analysis/recording stay full); 3000+ points skip line '
        'animation; a tap cancels animation. flutter_map simplify tolerance '
        'raised.',
  ),
  ChangelogEntry(
    version: 'v1.4.82 beta',
    date: '2026-08-29',
    noteTr:
        'Kayıt haritası kilitlenmesi: GpsRecorder her noktada + her saniye '
        'saat tikinde tüm FlutterMap (karo + tüm polyline) yeniden '
        'kuruluyordu; 2–3 dakika sonra UI donuyordu. Artık iskele sadece '
        'idle/kayıt geçişinde yenilenir; karolar durur, kırmızı çizgi '
        'eklenerek büyür, süre ayrı notifier ile akar. Referans rota çizimi '
        'de setState ile tüm ekranı 16ms\'de bir yıkmaz.',
    noteEn:
        'Recording map freeze: GpsRecorder rebuilt the whole FlutterMap '
        '(tiles + polyline) on every point and every 1 s clock tick; UI '
        'locked after 2–3 minutes. The scaffold now rebuilds only on '
        'idle/recording transitions; tiles stay, the red line grows, duration '
        'uses its own notifier. Reference routes no longer setState the whole '
        'screen every 16 ms.',
  ),
  ChangelogEntry(
    version: 'v1.4.81 beta',
    date: '2026-08-29',
    noteTr:
        'Kayıt haritası course-up işaret düzeltmesi: flutter_map dönüşü '
        'heading değil -heading (Android Auto ile aynı). Gidiş yukarı, eski '
        'noktalar aşağıda (gelinen yol arkada). Ayrıca son 15 dakikayı '
        'sığdıran ayrı bir özet tuşu (saat ikonu); "tüm iz" duruyor. Canlı '
        'takip hâlâ son 2–3 noktadan.',
    noteEn:
        'Recording map course-up: flutter_map rotation is -heading (same as '
        'Android Auto). Travel is up, older points sit below (the path behind '
        'you). A separate clock-icon control fits the last 15 minutes; “whole '
        'track” remains. Live follow still uses the last 2–3 points.',
  ),
  ChangelogEntry(
    version: 'v1.4.80 beta',
    date: '2026-08-29',
    noteTr:
        'Kayıt haritası course-up: kamera ve araç işareti artık kırmızı izin '
        'ucundan (son 2–3 nokta, eskiden → yeniye bearing) takip eder; '
        'önceden ayrı Geolocator akışı çizgiyle senkron olmayınca iz yukarı '
        'gidip aşağı kayıyormuş gibi görünüyordu. Idle konum hâlâ Dart GPS; '
        'kayıt başladıktan sonra tek kaynak native iz.',
    noteEn:
        'Recording map course-up: camera and vehicle marker follow the '
        'red-track tip (bearing from the last 2–3 points). A separate '
        'Geolocator stream used to desync so the track looked like it ran up '
        'then slid down. Idle location is still Dart GPS; once recording '
        'starts the native track is the only source.',
  ),
  ChangelogEntry(
    version: 'v1.4.79 beta',
    date: '2026-08-29',
    noteTr:
        'İz yükleme / harita: yeni GPX açılınca rota haritasında gösterilir. '
        'Tek iz tüm pencereye sığacak şekilde (MediaAtlas tarzı) otomatik '
        'yakınlaşır; birden fazla seçili iz birlikte kapsanır. Kayıt '
        'ekranında referans rota yüklenince de aynı sığdırma; "tüm iz" tuşu '
        'canlı kayıt + yüklenen referansları birlikte çerçeveler. Listeden '
        'tek seçim → tek rota haritası, çoklu → çoklu harita.',
    noteEn:
        'Opening a new GPX shows it on the route map. A single track '
        'auto-fits the window (MediaAtlas-style); several selected tracks are '
        'framed together. Loading a reference route on the recording screen '
        'fits the same way; “whole track” frames live recording plus '
        'references. One list pick → single-route map; several → multi-route '
        'map.',
  ),
  ChangelogEntry(
    version: 'v1.4.78 beta',
    date: '2026-08-28',
    noteTr:
        'Sürüş listesi: sıralama kayıttaki GPS tarihine (recordedAt) göre '
        'yeniden → eskiye; indeks Hive\'da önbellekli - liste her açılışta GPX '
        'dosyalarını yeniden okumaz. Aynı iz (nokta parmak izi) tekrar içe '
        'aktarılamaz: dosya seçince / "Şununla aç" ile aynı rota gelirse '
        '"zaten kayıtlı" uyarısı + mevcut kayıt açılır. Eski kayıtlara parmak '
        'izi bir kez arka planda yazılır.',
    noteEn:
        'Rides list sorts by GPS recordedAt newest→oldest; the index is '
        'cached in Hive so opening the list does not re-read GPX files. The '
        'same track (point fingerprint) cannot be imported twice: picker / '
        '“Open with” shows “already saved” and opens the existing ride. Older '
        'rides get a fingerprint written once in the background.',
  ),
  ChangelogEntry(
    version: 'v1.4.77 beta',
    date: '2026-08-28',
    noteTr:
        'Saat dilimi: çok günlük analiz ve gün filtreleri artık UTC yerine '
        'cihazın yerel takvim gününe göre bölünüyor (Türkiye UTC+3\'te gece '
        'yarısından sonraki noktalar önceki güne yazılıyordu - "dün '
        'gitmediğim kadar yol" görünümü). Kayıt tarihi/saati gösterimleri '
        'toLocal() ile düzeldi. Android: GPX/KML/KMZ için VIEW + SEND '
        'intent-filter eklendi - dosya yöneticisinde "Şununla aç" listesinde '
        'RideAtlas görünür; seçilince dosya içeriye alınır ve haritada açılır '
        '(paylaş menüsü de desteklenir).',
    noteEn:
        'Time zone: multi-day analysis and day filters split on the device’s '
        'local calendar day, not UTC (in Turkey UTC+3, post-midnight points '
        'were landing on the previous day). Displayed record dates use '
        'toLocal(). Android: VIEW + SEND intent-filters for GPX/KML/KMZ so '
        'RideAtlas appears in “Open with” and the share sheet.',
  ),
  ChangelogEntry(
    version: 'v1.4.76 beta',
    date: '2026-08-28',
    noteTr:
        'Web otomatik güncelleme (KDO mimarisi): web/sw.js service worker '
        'eklendi - sürümlü cache (rideatlas-vX.Y.Z), install\'da çekirdek '
        'shell precache, activate\'te eski cache temizliği + clients.claim(), '
        'SKIP_WAITING mesajı desteği; HTML network-first, diğer varlıklar '
        'cache-then-network. app_update.js SW\'yi kaydeder, bekleyen yeni SW '
        'görünce alttan sabit "Yeni sürüm hazır / Güncelle" banner\'ı gösterir '
        '(TR/EN/DE), Güncelle → SKIP_WAITING → controllerchange\'de tek '
        'seferlik reload; 60 sn\'de bir ve sekme öne gelince arka planda '
        'reg.update(). Sürüm değişiminde localStorage karşılaştırmalı tek '
        'seferlik hard-reload emniyeti. Sürüm + SW cache adı + ?v= buster\'lar '
        'deploy-web.yml tarafından build_info.dart\'tan otomatik damgalanır; '
        'elle senkron gerekmez. Header\'a ikon eklenmedi, yalnız alt banner; '
        'Android APK güncelleme akışına dokunulmadı.',
    noteEn:
        'Web auto-update (KDO-style): versioned service-worker cache, '
        'core-shell precache, old-cache cleanup, SKIP_WAITING; HTML '
        'network-first, other assets cache-then-network. A waiting SW shows '
        'the bottom “A new version is ready / Update” banner (TR/EN/DE); '
        'Update → one reload. Background update every 60 s and on tab focus. '
        'Version, cache name and ?v= busters are stamped from build_info.dart '
        'on deploy. Bottom banner only; Android APK flow unchanged.',
  ),
  ChangelogEntry(
    version: 'v1.4.75 beta',
    date: '2026-08-28',
    noteTr:
        'Sokak ve sade/siyasi haritada CARTO "API KEY REQUIRED" filigranı '
        'kalktı (OSM/Esri katmanları). Kayıt sırasında GPS sıçrama '
        'patlamaları canlı izden otomatik düzeltilir.',
    noteEn:
        'CARTO “API KEY REQUIRED” watermark removed from street and '
        'clean/political maps (OSM/Esri layers). GPS jump bursts during '
        'recording are auto-corrected on the live track.',
  ),
  ChangelogEntry(
    version: 'v1.4.74 beta',
    date: '2026-08-28',
    noteTr:
        'Güncelleme MedyaAtlas gibi arka planda indirilir: kilitleyen yüzde '
        'diyaloğu yok; ana/kayıt ekranındaki banner’da % görünür, uygulama '
        'kullanılabilir. APK doğrudan dosyaya akar (bellekte biriktirilmez).',
    noteEn:
        'Updates download in the background like MedyaAtlas: no blocking '
        'percent dialog; the home/recording banner shows % and the app stays '
        'usable. The APK streams to a file instead of buffering in memory.',
  ),
  ChangelogEntry(
    version: 'v1.4.73 beta',
    date: '2026-08-28',
    noteTr:
        'Konum tuşu canlı GPS okur; eski önbellek ve İstanbul varsayılanı '
        'kaldırıldı — Tampa vb. yerlerde yanlış şehre gitmez.',
    noteEn:
        'The location button reads live GPS; the old cache and Istanbul '
        'default are gone — it no longer jumps to the wrong city in Tampa and '
        'similar places.',
  ),
  ChangelogEntry(
    version: 'v1.4.72 beta',
    date: '2026-08-27',
    noteTr:
        'Yürürken oto-duraklama kalkar: düşük hızda veya ~20 m ilerleyince '
        'kayıt devam eder.',
    noteEn:
        'Auto-pause lifts when walking: recording resumes at low speed or '
        'after about 20 m of progress.',
  ),
  ChangelogEntry(
    version: 'v1.4.71 beta',
    date: '2026-08-27',
    noteTr:
        'Kayıtlı ride listesi kayıt tarihine göre (en yeni üstte) sıralanır.',
    noteEn:
        'The saved-rides list is sorted by recording date (newest first).',
  ),
  ChangelogEntry(
    version: 'v1.4.70 beta',
    date: '2026-08-27',
    noteTr:
        'Kayıt sürerken ana haritadaki konum tuşu kayıt haritasını canlı izle '
        'açar; kırmızı kayıt ikonu metin/istatistik sayfasına gider. Ana '
        'haritada da aynı kırmızı kayıt izi görünür — dışarıdaki ve kayıt '
        'haritası aynı yerde kalır.',
    noteEn:
        'While recording, the home map’s location button opens the recording '
        'map on the live track; the red REC icon goes to the stats page. The '
        'same red recording track is drawn on the home map so both maps stay '
        'aligned.',
  ),
  ChangelogEntry(
    version: 'v1.4.69 beta',
    date: '2026-08-27',
    noteTr:
        'İlk açılışta (ve stil değişiminde) harita bazen boş kalıyordu — '
        'flutter_map ilk kamera hareketini tile isteğine çevirmiyordu. Küçük '
        'bir tile “kick” eklendi; zoom’a basmadan harita boyanır.',
    noteEn:
        'On first open (and after a style change) the map could stay blank — '
        'flutter_map did not turn the first camera move into a tile request. '
        'A small tile “kick” paints the map without tapping zoom.',
  ),
  ChangelogEntry(
    version: 'v1.4.68 beta',
    date: '2026-08-27',
    noteTr:
        'Haritadaki araç/konum ("ride") ikonu küçültüldü ama beyaz kenar + '
        'gölge/glow ile daha vurgulu hale getirildi; uydu haritada ne devasa '
        'görünüyor ne de arkada kayboluyor.',
    noteEn:
        'The map vehicle/location (“ride”) icon is smaller but stronger with '
        'a white edge and glow, so it neither dominates satellite nor '
        'disappears.',
  ),
  ChangelogEntry(
    version: 'v1.4.67 beta',
    date: '2026-08-27',
    noteTr:
        'Yüklenen / açılan bir rotada kırmızı iz adım adım çizildikten sonra '
        'kaybolma sorunu düzeltildi. Sebep: geçici kırmızı çizgi, gün '
        'renklerine geçerken zaman damgası olmayan noktaları (veya eşleşmeyen '
        'gün filtresini) düşürebiliyordu; artık tam iz korunuyor.',
    noteEn:
        'A loaded route’s red track no longer vanished after the step-by-step '
        'draw. The temporary red line could drop untimestamped points (or a '
        'mismatched day filter) when switching to day colors; the full track '
        'is kept.',
  ),
  ChangelogEntry(
    version: 'v1.4.66 beta',
    date: '2026-08-27',
    noteTr:
        'Kayıt haritasında "konumuma dön" artık her zaman cihaz GPS konumuna '
        'sabit yakın zoom ile gider (kayıt ederken / etmezken aynı; önceden '
        'takip açıkken hiç tepki vermiyor veya ara zoom / tween kalıntısına '
        'zıplayabiliyordu). Tüm kaydı göstermek için zoom-out ikonu ayrı '
        'duruyor.',
    noteEn:
        'On the recording map, “back to my location” always goes to device '
        'GPS at a fixed close zoom (recording or idle). The zoom-out icon '
        'remains for showing the whole recording.',
  ),
  ChangelogEntry(
    version: 'v1.4.65 beta',
    date: '2026-08-27',
    noteTr:
        'Android/web derlemesi düzeltildi (kayıt ekranında eksik gpx_parser '
        'import). Üstteki "N rota" ile listeden yeniden seçim (1.4.64) bu '
        'sürümle telefona iner.',
    noteEn:
        'Android/web build fixed (missing gpx_parser import on the recording '
        'screen). Re-picking from the top “N routes” chip (1.4.64) now ships '
        'to the phone.',
  ),
  ChangelogEntry(
    version: 'v1.4.64 beta',
    date: '2026-08-27',
    noteTr:
        'Çoklu rota haritasında üstteki "N rota" başlığına basınca tüm '
        'kayıtların listesi açılıyor; Hepsi / tek tek seçip Göster ile '
        'haritayı yeniden yükleyebiliyorsunuz (yine kademeli çizim).',
    noteEn:
        'On the multi-route map, tapping the top “N routes” title opens the '
        'full list; All / pick-then-Show reloads the map (still drawn '
        'progressively).',
  ),
  ChangelogEntry(
    version: 'v1.4.63 beta',
    date: '2026-08-27',
    noteTr:
        'Kayıt haritasındaki rota seçim diyaloğu: "Kaydet" → "Göster", '
        '"Hepsi" kutusu ile tek dokunuşta hepsini seç/kaldır, "Temizle" '
        'kaldırıldı. Çoklu "Haritada göster" artık önce haritayı açıp her '
        'rotayı arka planda parse ederek adım adım çiziyor (önceden hepsi '
        'bitene kadar kilitleniyordu / "cevap vermiyor").',
    noteEn:
        'Recording-map route picker: “Save” → “Show”, All checkbox to '
        'select/clear everything, Clear removed. Multi “Show on map” opens '
        'the map first and parses each route in the background so the UI no '
        'longer freezes until everything is ready.',
  ),
  ChangelogEntry(
    version: 'v1.4.62 beta',
    date: '2026-08-26',
    noteTr:
        'Android güncelleme banner\'ı artık sadece ana haritada değil; kayıt '
        'haritası ve veri/istatistik ekranında da "Güncelle" ile görünüyor. '
        'İndirme yüzdesi düzeltildi: GitHub CDN çoğu zaman Content-Length '
        'göndermiyordu (yüzde "…" kalıyordu); artık Releases API\'deki APK '
        'boyutu kullanılıyor ("%26 — RideAtlas.apk").',
    noteEn:
        'The Android update banner is no longer home-only; it also appears on '
        'the recording map and data/stats screen. Download percent fixed: '
        'GitHub’s CDN often omits Content-Length; the Releases API APK size '
        'is used (“26% — RideAtlas.apk”).',
  ),
  ChangelogEntry(
    version: 'v1.4.61 beta',
    date: '2026-08-26',
    noteTr:
        'Android APK derlemesi düzeltildi: v1.4.58\'deki foto konum düzeltmesi '
        'photo_manager ile latlong2 LatLng isim çakışması yüzünden CI\'da '
        'kırılıyordu; android-latest sürümü 1.4.56\'da kalmıştı. Bu yüzden '
        'telefonda 60 görünmüyordu. Derleme onarıldı; önceki sürümlerin '
        '(ayarlar, GPX animasyonu, tek Güncelle + yüzde indirme) özellikleri '
        'bu APK\'da.',
    noteEn:
        'Android APK build fixed: v1.4.58’s photo-location change collided '
        'photo_manager with latlong2 LatLng and broke CI, leaving '
        'android-latest on 1.4.56. Build repaired; settings, GPX animation, '
        'and one-button Update + percent download are in this APK.',
  ),
  ChangelogEntry(
    version: 'v1.4.60 beta',
    date: '2026-08-26',
    noteTr:
        'Android güncelleme akışı sadeleştirildi (MedyaAtlas tarzı): tek '
        '"Güncelle" düğmesi; sonrasında indirme yüzdesi ("٪26 — '
        'RideAtlas.apk") gösterilip kurulum otomatik açılıyor. Açılışta da '
        'aynı tek-düğmeli teklif var; banner\'da kapat/iptal karmaşası '
        'kaldırıldı.',
    noteEn:
        'Android update flow simplified (MedyaAtlas-style): one Update '
        'button, then download percent (“26% — RideAtlas.apk”) and the '
        'installer opens. Launch uses the same one-button offer; banner '
        'dismiss/cancel clutter is gone.',
  ),
  ChangelogEntry(
    version: 'v1.4.59 beta',
    date: '2026-08-26',
    noteTr:
        'GPX/KML açılınca (özellikle çok noktalı dosyalarda) harita artık '
        'hemen geliyor: önce rota sınırlarına sığdırılmış boş harita, sonra '
        'konumlar okundukça iz adım adım animasyonla çiziliyor. Parse ve '
        'GPS-glitch filtresi arka planda (UI kilitlemeden) çalışıyor; içe '
        'aktarma da aynı şekilde donmuyordu. Önceden uzun dosyada tüm '
        'noktalar işlenene kadar spinner\'da kalınıyor, "açılmıyor" gibi '
        'görünüyordu.',
    noteEn:
        'Opening GPX/KML (especially large files) shows the map immediately: '
        'an empty map fitted to bounds, then the track animates as points '
        'arrive. Parse and the GPS-glitch filter run off the UI isolate so '
        'import no longer freezes on a spinner.',
  ),
  ChangelogEntry(
    version: 'v1.4.58 beta',
    date: '2026-08-26',
    noteTr:
        'Ana haritada Ayarlar düğmesi artık liste düğmesiyle aynı yuvarlak '
        'görünümde (uydu haritasında kaybolmuyordu). Kayıt ekranına da '
        'Ayarlar eklendi. Kayıt haritasında isteğe bağlı "kayıtlı rota '
        'göster" tuşu: bir veya birden fazla GPX/kayıtlı rota seçilince canlı '
        'iz altında çiziliyor; istemezseniz hiç seçilmez. Ayrıca kayıt '
        'sırasında çekilen foto/videoların konumu Android\'de artık otomatik '
        'bulunuyor: galeri GPS → EXIF → kayıt anındaki GPS izi (önceden '
        'MediaStore konumu boş gelince hep elle işaretletiyordu).',
    noteEn:
        'Home Settings matches the list button’s round look (it used to '
        'vanish on satellite). Settings also on the recording screen. '
        'Optional “show saved routes” on the recording map draws selected GPX '
        'under the live track. Photos/videos taken while recording get a '
        'location automatically on Android: gallery GPS → EXIF → the '
        'recording track.',
  ),
  ChangelogEntry(
    version: 'v1.4.56 beta',
    date: '2026-08-26',
    noteTr:
        'Yüklenen / açılan bir rotada haritayı sağa-sola kaydırırken veya '
        'küçültüp büyütürken uygulamanın kilitlenmesi düzeltildi. Sebep: '
        'parmak hareketlerindeki minik harita dönüşü her karede tüm ekranı '
        'yeniden kuruyor, uzun izlerde mola tespiti ve gün bölme hesabı '
        'tekrar tekrar çalışıyordu. Artık bu hesaplar rota yüklenince bir kez '
        'yapılıyor; pusula dönüşü de haritayı yeniden çizmeden güncelleniyor.',
    noteEn:
        'Panning or pinching a loaded route no longer freezes the app. Tiny '
        'map rotations were rebuilding the whole screen every frame and '
        're-running stop detection / day splits. Those run once on load; '
        'compass rotation updates without a full redraw.',
  ),
  ChangelogEntry(
    version: 'v1.4.55 beta',
    date: '2026-08-25',
    noteTr:
        'Kayıt kontrolleri yeniden düzenlendi: kayıt sırasında tek tuş '
        '(Duraklat); duraklatınca Devam / Kaydet / Sıfırla. Kaydet oturumu '
        'bitirmez - kayıt sonrası "devam et veya sıfırla" seçilir; '
        'kaydedilmişse sıfırlama uyarısız, kaydedilmemiş veri varsa onay '
        'sorulur. Harita sayfasına "tüm kaydı göster" tuşu eklendi (kuzey '
        'yukarı, tüm rota ekrana sığar); konum tuşu o anki pozisyona ve '
        'course-up takibe döndürür. Haritanın "yukarı gidip aşağı akma" '
        'titremesi çözüldü: araç işareti artık kamerayla aynı animasyonda '
        'ilerliyor (fix gelince öne zıplayıp geri akmıyor) ve her fixte '
        'birikip CPU yakan eski animasyon dinleyicileri temizleniyor. Ayrıca '
        'idle haritada konuma ortalama/takip onarıldı.',
    noteEn:
        'Recording controls: one Pause button while recording; when paused, '
        'Resume / Save / Reset. Save does not end the session — afterwards '
        'choose resume or reset (silent if just saved, confirm if unsaved). '
        '“Show whole recording” on the map page (north-up, fit); location '
        'returns to the current position and course-up follow. Vehicle marker '
        'moves with the same camera animation so it no longer jumps ahead and '
        'slides back. Idle-map location average/follow repaired.',
  ),
  ChangelogEntry(
    version: 'v1.4.54 beta',
    date: '2026-08-23',
    noteTr:
        'Kayıt devamı tamamlandı: sadece "kayıt/pause" bayrağı değil, '
        'başlangıç saati, tamamlanmış molalar ve süren duraklatma anı da '
        'diskte saklanıyor. Yeniden açılışta mesafe (tüm GPS noktalarından), '
        'son konum, aktif/duraklatılmış mod ve süreler kaldığı yerden '
        'geliyor. Kayıt yokken (idle) dosya yazılmaz - açılışta kayıt '
        'başlamaz. v1.4.53\'teki 2 sn GPS ve course-up düzeltmeleri duruyor.',
    noteEn:
        'Recording resume is complete: not only the recording/pause flag — '
        'start time, finished rests, and the in-progress pause instant are '
        'stored. On reopen, distance (from all GPS points), last location, '
        'active/paused mode and timers come back. Idle writes nothing — '
        'launch does not start recording. v1.4.53’s 2 s GPS and course-up '
        'fixes remain.',
  ),
  ChangelogEntry(
    version: 'v1.4.53 beta',
    date: '2026-08-23',
    noteTr:
        'Kayıt stabilitesi: (1) Uygulama kilitlenince / yanlışlıkla kapanınca '
        '/ OEM öldürünce kayıt oturumu diskte saklanıyor; tekrar açılışta '
        'Motion GPX gibi kaldığı yerden devam ediyor (kayıttaysa kayıt, '
        'duraklatılmışsa duraklatılmış; idle ise idle). Eski "açılışta yetim '
        'noktaları sil" davranışı kaldırıldı. (2) Aktif GPS aralığı 1 sn → 2 '
        'sn; harita konum akışı ve native poll de uyumlandı - saniyelik çift '
        'GPS yükü telefonu yoruyordu. (3) Kayıt bilgi sayfasındayken harita '
        'Offstage ile bağlı kalıyor; haritaya geçince course-up (yön yukarı) '
        'yeniden etkin - önceki MapController kopması giderildi.',
    noteEn:
        'Recording stability: (1) If the app is killed, the session is on '
        'disk and resumes where it left off (recording, paused, or idle). The '
        'old “delete orphan points on launch” behavior is gone. (2) Active '
        'GPS interval 1 s → 2 s; map stream and native poll match. (3) The '
        'map stays attached via Offstage on the info page so course-up works '
        'again when you return — the previous MapController detach is gone.',
  ),
  ChangelogEntry(
    version: 'v1.4.52 beta',
    date: '2026-08-22',
    noteTr:
        'Kayıt rakımı düzeltildi. Android GPS Location.altitude WGS84 '
        'elipsoid yüksekliği verir; birçok uygulama deniz seviyesi (MSL / '
        'ortometrik) gösterir - fark geoid undülasyonu yüzünden bölgeye göre '
        'genelde 20–40 m. Kullanıcı başka programda ~5 m görürken '
        'RideAtlas\'ta −29 m (yaklaşık 25 m düşük) bildirdi. '
        'RecordingLocationService artık AltitudeConverterCompat ile her fixi '
        'MSL\'e çeviriyor; dönüşüm başarısız olursa eski elipsoid değerine '
        'düşülüyor. Canlı yükseklik, min/maks irtifa, tırmanış/iniş ve '
        'kaydedilen GPX aynı düzeltilmiş rakımı kullanır.',
    noteEn:
        'Recording altitude fixed. Android Location.altitude is WGS84 '
        'ellipsoid; many apps show MSL / orthometric — typically 20–40 m of '
        'geoid undulation. A rider saw ~5 m elsewhere and −29 m here. '
        'RecordingLocationService now converts each fix with '
        'AltitudeConverterCompat (falls back to ellipsoid). Live altitude, '
        'min/max, climb/descent and saved GPX use the corrected height.',
  ),
  ChangelogEntry(
    version: 'v1.4.51 beta',
    date: '2026-08-15',
    noteTr:
        'Kullanıcı "kayıt yaparken sık sık kendi kendine kapanıyor" diye '
        'bildirdi (özellikle uzun sürüşlerde, tam da o gün üzerinde '
        'çalıştığımız 10+ saatlik/36.628 noktalık örnek gibi). Kod '
        'incelemesinde kök sebep bulundu: GpsRecorder.distanceKm getter\'ı her '
        'okunduğunda TÜM nokta listesini baştan toplayarak mesafeyi yeniden '
        'hesaplıyordu, ve kayıt ekranı bu değeri her GPS güncellemesinde '
        '(saniyede bir) okuyordu - kayıt uzadıkça bu iş katlanarak '
        'ağırlaşıyordu (klasik O(n²) davranış): birkaç saat sonra saniyede '
        'binlerce mesafe hesabına çıkıp ekranı dondurabiliyor, bu da '
        'uygulamanın "kapanması" gibi algılanan bir duruma yol açabiliyordu. '
        'Aynı sorun points getter\'ında da vardı (her okumada tüm liste '
        'kopyalanıyordu). İkisi de artık O(1): mesafe her yeni nokta '
        'geldiğinde tek seferlik eklenerek tutuluyor, points ise kopyalamak '
        'yerine canlı bir görünüm döndürüyor. Kayıt süresi ne kadar uzarsa '
        'uzasın her güncelleme artık sabit hızda kalıyor.',
    noteEn:
        'Long recordings could “close themselves”. GpsRecorder.distanceKm '
        'recomputed the whole point list on every read, and the recording '
        'screen read it on every GPS update — O(n²) that froze the UI after '
        'hours. The points getter copied the list every time too. Both are '
        'O(1): distance is accumulated, points returns a live view.',
  ),
  ChangelogEntry(
    version: 'v1.4.50 beta',
    date: '2026-08-15',
    noteTr:
        'Android\'de v1.4.49\'un açılışta bembeyaz ekranda kalma regresyonu '
        'düzeltildi. Kök sebep: karo isteğine User-Agent koymak için '
        'oluşturulan const header map\'i, flutter_map TileLayer\'ın Android\'de '
        'çağırdığı headers.putIfAbsent ile uyumsuzdu (unmodifiable map → '
        'UnsupportedError → release\'te boş beyaz ekran). Header map artık '
        'değiştirilebilir; Topo yine resmi OpenTopoMap.',
    noteEn:
        'v1.4.49’s launch white-screen regression on Android: a const '
        'User-Agent header map was unmodifiable and TileLayer’s '
        'headers.putIfAbsent threw UnsupportedError (blank release screen). '
        'The header map is mutable; Topo stays official OpenTopoMap.',
  ),
  ChangelogEntry(
    version: 'v1.4.49 beta',
    date: '2026-08-15',
    noteTr:
        'Topo katmanındaki openmaps.fr "Limited Access" uyarısı giderildi. '
        'Sunucu, beğenmediği User-Agent isteklerine gerçek harita yerine '
        'politika uyarı görseli döndürüyordu. Topo yeniden resmi OpenTopoMap '
        '(tile.opentopomap.org) kaynağına alındı; karo istekleri RideAtlas '
        '(com.rideatlas.app) User-Agent ile gidiyor. v1.4.48\'deki tam-katman '
        'sıfırlamama düzeltmesi duruyor.',
    noteEn:
        'Topo “Limited Access” from openmaps.fr is gone. The server returned '
        'a policy image for User-Agents it disliked. Topo is back on official '
        'OpenTopoMap (tile.opentopomap.org) with a RideAtlas '
        '(com.rideatlas.app) User-Agent. v1.4.48’s no-full-layer-reset fix '
        'remains.',
  ),
  ChangelogEntry(
    version: 'v1.4.48 beta',
    date: '2026-08-15',
    noteTr:
        'Topo/harita "kare kare yanıp sönme" düzeltildi. Kök sebep: bir karo '
        'yüklenemeyince (OpenTopoMap hız limiti) tüm TileLayer\'ın '
        'sıfırlanması - her 2 saniyede bir bütün harita yeniden çekiliyor, '
        'başarılı/başarısız karolar karışık görünüyordu. Bu tam-katman retry '
        'kaldırıldı; yalnızca budanan hatalı karolar yeniden deneniyor. Stil '
        'değişince ValueKey ile önbellek temizleniyor. Renkli topo, OTM '
        'uyumlu openmaps.fr sunucusuna taşındı (maxNativeZoom 17).',
    noteEn:
        'Topo/map “flashing tiles” fixed. A failed tile (OpenTopoMap rate '
        'limit) used to reset the whole TileLayer every 2 s. Only pruned bad '
        'tiles are retried. Style changes clear the cache via ValueKey. Color '
        'topo moved to an OTM-compatible openmaps.fr host (maxNativeZoom 17).',
  ),
  ChangelogEntry(
    version: 'v1.4.47 beta',
    date: '2026-08-15',
    noteTr:
        'Topo katmanı Esri World_Topo_Map\'ten OpenTopoMap\'e alındı: yükseklik '
        'renkleri (yeşil → sarı → kahverengi) ve konturlar yeniden belirgin. '
        'Soluk "sokak-topo" görünümü yerine renkli outdoor stil. Tile '
        'sunucusu bazen hız limiti koyarsa mevcut otomatik yeniden deneme gri '
        'kareleri dolduruyor.',
    noteEn:
        'Topo layer moved from Esri World_Topo_Map to OpenTopoMap: elevation '
        'colors (green → yellow → brown) and contours are visible again. '
        'Outdoor style instead of a pale street-topo. Automatic retry still '
        'fills grey tiles if the host rate-limits.',
  ),
  ChangelogEntry(
    version: 'v1.4.46 beta',
    date: '2026-08-15',
    noteTr:
        'Uygulama ikonu yenilendi: kırmızı pin + harita ızgarası korunarak '
        'kıvrılan yolun altına motosiklet silüeti eklendi. Harita türü '
        'seçicide sıra Sokak / Uydu / Topo / Koyu / Sade olacak şekilde '
        'düzenlendi (etiket: Topo). Kayıt ekranındaki canlı haritaya da '
        'katman düğmesi eklendi - tercih diğer harita ekranlarıyla ortak '
        'saklanıyor. Android/iOS/web/masaüstü launcher ikonları yeni '
        'kaynaktan yeniden üretildi.',
    noteEn:
        'App icon refreshed: red pin + map grid kept, motorcycle silhouette '
        'added under the winding road. Map-type picker order is Street / '
        'Satellite / Topo / Dark / Clean (label: Topo). The live recording '
        'map also has a layer button — preference is shared. Launcher icons '
        'regenerated for Android/iOS/web/desktop.',
  ),
  ChangelogEntry(
    version: 'v1.4.45 beta',
    date: '2026-08-14',
    noteTr:
        'Kullanıcı, v1.4.44\'teki sıçrama filtresinin haritadaki büyük '
        'zıplamayı yine de temizlemediğini gösterdi ve gerçek rota dosyasını '
        'paylaştı. Dosyayı inceleyince kök sebep netleşti: sıçrama tek bir '
        '"anlık imkansız" hız değil, cihaz dururken GPS\'in yaklaşık bir '
        'dakika boyunca ~1.7km uzakta donup kalıp sonra gerçek konuma geri '
        'dönmesiydi - her tek adım kendi başına "sadece hızlı" (~140 km/s) '
        'görünüyordu, mevcut mutlak hız eşiğini (300 km/s) geçmiyordu. '
        'gpx_parser.dart\'a yeni bir findExcursionPointIndices dedektörü '
        'eklendi: rota aniden uzağa sıçrayıp birkaç ölçüm içinde neredeyse '
        'aynı noktaya geri dönüyorsa (gerçek bir sürüşün asla yapmayacağı bir '
        'şey), aradaki noktalar GPS aksaklığı sayılıp otomatik filtreye ve '
        '"Anormal noktaları düzenle" ekranına dahil ediliyor. Kullanıcının '
        'paylaştığı 36.628 noktalık gerçek dosya üzerinde doğrulandı: '
        'algoritma tam olarak bozuk 11 noktayı buluyor, başka hiçbir gerçek '
        'sürüş/duraklama anını yanlışlıkla işaretlemiyor.',
    noteEn:
        'The v1.4.44 jump filter still left a big spike on a real '
        '36,628-point file. The glitch was not one impossible speed: GPS '
        'froze ~1.7 km away for about a minute then snapped back, each step '
        'only ~140 km/h (under the 300 km/h cap). New '
        'findExcursionPointIndices: if the route leaps away and returns to '
        'nearly the same point within a few fixes, those points are treated '
        'as a GPS fault and appear in the anomaly editor. On that file it '
        'flags exactly the 11 bad points and no real riding/stops.',
  ),
  ChangelogEntry(
    version: 'v1.4.44 beta',
    date: '2026-08-14',
    noteTr:
        'Kullanıcı, kayıtlı bir rotanın "Ortalama hız"ının başka bir GPX '
        'programındakiyle uyuşmadığını bildirdi. İnceleme RideAtlas\'ın kendi '
        'içinde de bir tutarsızlık ortaya çıkardı: Özet sekmesindeki "Aktif '
        'sürüş süresi" molaları >=10dk eşiğiyle hesaplarken, hemen yanındaki '
        '"Ortalama hız" 1km/s altındaki her segmenti ayrıca tamamen hesap '
        'dışı bırakan farklı bir yöntem kullanıyordu - iki rakam Mesafe/Süre '
        'ile çarpıldığında birbirini tutmuyordu. Artık "Ortalama hız" da '
        '"Aktif sürüş süresi" ile aynı süreyi kullanıyor. Aynı bildirimde, '
        'tek bir kötü GPS noktasından kaynaklanan haritadaki "sıçrama" da '
        'gündeme geldi - iki parçalı çözüm eklendi: (1) böyle noktalar artık '
        'harita ve istatistik hesaplarında otomatik olarak yok sayılıyor '
        '(dosya değişmiyor), (2) "Rotalar" listesindeki ⋮ menüsüne "Anormal '
        'noktaları düzenle" eklendi - tespit edilen noktaları görüp '
        'istediklerinizi kalıcı olarak rotadan silebilirsiniz.',
    noteEn:
        'Average speed disagreed with another GPX app — and with RideAtlas '
        'itself: Overview “Active riding time” used ≥10 min rests while '
        'Average speed dropped every <1 km/h segment. Average speed now uses '
        'the same duration as active riding. Single bad GPS jumps are ignored '
        'on the map and in stats (file unchanged), and Routes ⋮ has “Edit '
        'anomalous points” to delete flagged points permanently.',
  ),
  ChangelogEntry(
    version: 'v1.4.43 beta',
    date: '2026-08-14',
    noteTr:
        'v1.4.42\'deki düzeltme (duraklamada düşük hassasiyetli konuma geçmeyi '
        'engellemek) yeterli değilmiş - kullanıcı gerçek bir sürüşte ekran '
        'görüntüsüyle yine "Otomatik duraklatıldı"nın hiç kapanmadığını, '
        'sadece elle duraklat/devam ettirince çalıştığını gösterdi. Kod '
        'içinde asıl sebep bulundu: RecordingLocationService.kt\'deki konum '
        'callback\'i duraklama sırasında gelen HER fix\'i "if (isPaused) '
        'return" ile en baştan yok sayıyordu - GPS\'in kendisi düzelse bile '
        'hiçbir konum Flutter tarafına ulaşmıyordu, o yüzden hızı kontrol '
        'edip duraklamayı kaldıran mantık hiç çalıştırılamıyordu. Elle '
        'duraklat/devam ettir çalışıyordu çünkü o buton konum beklemeden '
        'direkt durumu değiştiriyor. Düzeltildi: duraklama sırasında da her '
        'konum artık Flutter\'a iletiliyor (hız kontrolü için) - sadece '
        'kayıtlı rotaya eklenmiyor, o davranış değişmedi.',
    noteEn:
        'v1.4.42 (stay on high-accuracy GPS while paused) was not enough — '
        'auto-pause never cleared unless Pause/Resume was tapped. '
        'RecordingLocationService dropped every paused fix (`if (isPaused) '
        'return`), so Flutter never saw speed to lift the pause. Manual '
        'buttons worked because they change state without a fix. Paused '
        'locations are now forwarded for speed checks but still not appended '
        'to the saved track.',
  ),
  ChangelogEntry(
    version: 'v1.4.42 beta',
    date: '2026-08-14',
    noteTr:
        'v1.4.38/v1.4.41\'deki pil tasarrufu değişikliğinde daha ciddi bir '
        'hata vardı: kullanıcı mola sonrası bazen "Otomatik duraklatıldı" '
        'yazısının hiç kapanmadığını, gerçekten takılı kaldığını bildirdi '
        '(geçen sürümde ele alınan birkaç saniyelik gecikmeden farklı). Kök '
        'sebep: duraklama sırasında GPS isteği düşük hassasiyetli '
        '(PRIORITY_BALANCED_POWER_ACCURACY) moddaydı - bu Android\'in GPS çipi '
        'yerine WiFi/baz istasyonu konumlamasına geçmesine izin veriyor, ve '
        'bu kaynaklar genelde hız bilgisi vermiyor (0 dönüyor). Gerçekten '
        'hareket etmeye başlasanız bile ölçülen hız sıfıra yakın kalıp 6km/s '
        'eşiğini hiç geçemiyor, duraklama asla kapanmıyordu. Duraklama '
        'sırasında GPS çipi devrede kalacak şekilde (PRIORITY_HIGH_ACCURACY, '
        'sadece yenileme aralığı seyrek) düzeltildi - pil tasarrufu yenileme '
        'aralığından geliyor zaten, artık gerçek hız her zaman ölçülüyor.',
    noteEn:
        'A worse side-effect of the v1.4.38/41 battery change: “Auto-paused” '
        'could stick forever. While paused, GPS used '
        'PRIORITY_BALANCED_POWER_ACCURACY (Wi‑Fi/cell), which often reports 0 '
        'speed so the 6 km/h resume threshold never tripped. Pause now keeps '
        'PRIORITY_HIGH_ACCURACY and only lengthens the interval — real speed '
        'is always measured.',
  ),
  ChangelogEntry(
    version: 'v1.4.41 beta',
    date: '2026-08-14',
    noteTr:
        'v1.4.38\'deki pil tasarrufu değişikliğinin yan etkisi düzeltildi: '
        'duraklama sırasında GPS 8 saniyede bire kadar yavaşlıyordu, bu da '
        'tekrar harekete geçtiğinizde "Otomatik duraklatıldı" yazısının 8 '
        'saniyeye kadar ekranda asılı kalmasına neden oluyordu - kullanıcı '
        'bir ekran görüntüsüyle bunu yakaladı. Duraklamadaki GPS yenileme '
        'aralığı 3 saniyeye düşürüldü (aktif haldeki 1sn\'nin 3 katı - hâlâ '
        'ciddi pil tasarrufu sağlıyor) - harekete geçiş artık çok daha hızlı '
        'fark ediliyor.',
    noteEn:
        'v1.4.38’s battery save slowed paused GPS to every 8 s, so '
        '“Auto-paused” could linger up to 8 s after you moved. Paused '
        'interval is now 3 s (3× the 1 s active rate) — still a clear battery '
        'win, much faster resume.',
  ),
  ChangelogEntry(
    version: 'v1.4.40 beta',
    date: '2026-08-14',
    noteTr:
        'v1.4.39\'daki isim sorma diyaloğunda gerçek bir hata vardı: girilen '
        'isim doğru soruluyordu ama Android\'in paylaşım ekranına geçince '
        'dosya rastgele/anlamsız bir isimle (UUID benzeri) görünüyordu - '
        'XFile.fromData Android\'de verilen ismi paylaşım sayfasına '
        'taşımıyormuş. Artık dosya önce gerçek adıyla diske yazılıp öyle '
        'paylaşılıyor, paylaşım ekranında da doğru isim görünüyor. Web tarafı '
        'etkilenmedi, orada zaten doğru çalışıyordu.',
    noteEn:
        'The v1.4.39 name dialog asked for the right name, but Android’s '
        'share sheet showed a UUID-like filename — XFile.fromData does not '
        'pass the name through. The file is now written to disk under the '
        'real name before sharing. Web was already correct.',
  ),
  ChangelogEntry(
    version: 'v1.4.39 beta',
    date: '2026-08-14',
    noteTr:
        'Harita ekranındaki paylaş/dışa aktar akışı artık format sorusundan '
        'sonra dosya ismini de soruyor - varsayılan olarak rotanın kayıtlı '
        'ismi geliyor, isterseniz değiştirebilirsiniz. Özellikle '
        'birleştirilmiş rotalarda (otomatik "A + B" ismiyle gelenler) '
        'faydalı.',
    noteEn:
        'Share/export on the map now asks for a file name after the format, '
        'defaulting to the saved route name. Especially useful for merged '
        'routes that arrive as “A + B”.',
  ),
  ChangelogEntry(
    version: 'v1.4.38 beta',
    date: '2026-08-14',
    noteTr:
        'Pil tasarrufu: incelendiğinde ortaya çıktı ki oto-duraklama ve '
        'manuel duraklama sadece görsel/kayıt filtresiydi - GPS çipi arkada '
        'hâlâ tam hızda (1 saniyede bir, yüksek hassasiyet) çalışıp pil '
        'tüketmeye devam ediyordu. Artık duraklama başlar başlamaz native GPS '
        'isteği yavaşlıyor (8 saniyede bir, düşük güç modu); hareket '
        'algılanır algılanmaz eski hızına (1sn/yüksek hassasiyet) dönüyor. '
        'Hem otomatik hem elle duraklatma bu değişiklikten yararlanıyor.',
    noteEn:
        'Battery: auto-pause and manual pause were only a visual/record '
        'filter — the GPS chip still ran at 1 s high accuracy. As soon as '
        'pause starts, the native request slows (every 8 s, low power) and '
        'returns to 1 s / high accuracy when motion is detected. Both auto '
        'and manual pause use this.',
  ),
  ChangelogEntry(
    version: 'v1.4.37 beta',
    date: '2026-08-14',
    noteTr:
        'Test sürümü: yerel Flutter + Android SDK derleme zinciri doğrulandı. '
        'Ürün davranışı v1.4.36 ile aynı; etiket yeni APK/web yayınının '
        'geldiğini doğrulamak için.',
    noteEn:
        'Test build: local Flutter + Android SDK toolchain verified. Product '
        'behavior matches v1.4.36; the label only confirms a new APK/web '
        'release.',
  ),
  ChangelogEntry(
    version: 'v1.4.36 beta',
    date: '2026-08-13',
    noteTr:
        'İki ekran görüntüsüyle yakalanan iki gerçek harita hatası '
        'düzeltildi: (1) Kırmızı rota çizgisinde ara sıra beliren keskin '
        '"sıçrama"lar (özellikle kavşak/yüksek bina yakınlarında) - GPS '
        'servisinden gelen fiziksel olarak imkansız hızlı sıçramalar artık '
        'rotaya hiç eklenmiyor, kaydedilen iz temiz kalıyor. (2) Harita '
        'yön-takip (course-up) modunun "neden yukarı gitmiyor" sorunu - kök '
        'neden bulundu: bilgi sayfasından haritaya her geçişte, harita '
        'widget\'ı yeniden kurulurken flutter_map kütüphanesinin kendi iç '
        'olayı ("boyut değişti") yanlışlıkla "kullanıcı haritayı elle '
        'kaydırdı" sanılıp yön-takip modunu sessizce kapatıyordu - siz hiç '
        'dokunmasanız bile. Artık sadece gerçek sürükleme/yakınlaştırma '
        'hareketleri modu kapatıyor.',
    noteEn:
        'Two real map bugs from screenshots: (1) Sharp “jumps” on the red '
        'line (junctions / tall buildings) — physically impossible GPS hops '
        'are no longer added. (2) Course-up looking like it was not heading '
        'up: leaving the info page rebuilt the map and flutter_map’s “size '
        'changed” event was treated as a user pan, silently turning follow '
        'off. Only real drag/pinch now disables follow.',
  ),
  ChangelogEntry(
    version: 'v1.4.35 beta',
    date: '2026-08-13',
    noteTr:
        'Kayıt ekranının canlı bilgi sayfasındaki kartların varsayılan sırası '
        'değişti: Aktif sürüş süresi/Mesafe, Mola süresi/Son moladan bu yana, '
        'Ortalama hız/Maks. hız, Maks. irtifa/Min. irtifa, İniş/Tırmanış, en '
        'altta tek başına Yükseklik. Bu sadece varsayılan - kartları basılı '
        'tutup sürükleyerek istediğiniz gibi değiştirmeye devam '
        'edebilirsiniz.',
    noteEn:
        'Default order of live recording cards: Active time/Distance, '
        'Rest/Since last rest, Average/Max speed, Max/Min altitude, '
        'Descent/Climb, Elevation alone at the bottom. Still fully '
        'rearrangeable in Settings.',
  ),
  ChangelogEntry(
    version: 'v1.4.34 beta',
    date: '2026-08-12',
    noteTr:
        'Aktif sürüş süresi mantığı gözden geçirildi: artık her durduğunuzda '
        '(kısa duraklama da olsa) ekranda anında donuyor - önceden hiç '
        'donmuyordu, sadece 10dk+ molalar sonradan düşülüyordu. Tekrar '
        'harekete geçince: duraklama 10 dakikanın altındaysa o süre geriye '
        'dönük olarak aktif sürüşe eklenir (küçük bir sıçrama görürsünüz), 10 '
        'dakika ve üzeriyse mola sayılır. Toplam süre = Aktif sürüş + Mola '
        'süresi eşitliği hep korunuyor. Ayrıca "Son moladan bu yana" sayacı, '
        'devam eden bir molayı (10dk+ duraklamayı) artık kendi içine katmıyor '
        '- mola sürerken sıfırda duruyor, mola bitip tekrar harekete geçince '
        'sıfırdan saymaya başlıyor.',
    noteEn:
        'Active riding time now freezes as soon as you stop (even briefly); '
        'before it never froze and only subtracted 10+ min rests later. On '
        'resume, a rest under 10 minutes is added back to active time (a '
        'small jump); 10+ minutes stays a rest. Total = Active + Rest always '
        'holds. “Since last rest” no longer includes an in-progress 10+ min '
        'rest — it stays at zero during the rest and restarts when you move.',
  ),
  ChangelogEntry(
    version: 'v1.4.33 beta',
    date: '2026-08-12',
    noteTr:
        'Kayıt ekranının canlı bilgi sayfasındaki kartlar çok küçük '
        'kalıyordu, altta boş yer duruyordu - artık her satır kalan dikey '
        'alanı doldurup büyüyor, kartların içindeki yazı da kart boyutuna '
        'göre otomatik ölçekleniyor. Ayrıca artık Ayarlar\'a gitmeden, tam '
        'telefon ana ekranındaki uygulama ikonlarını taşıma gibi: bir kartı '
        'parmakla basılı tutup başka bir kartın üzerine sürükleyip bırakarak '
        'yerlerini doğrudan değiştirebilirsiniz.',
    noteEn:
        'Live recording cards were tiny with empty space below — each row now '
        'fills leftover height and type scales with the card. You can '
        'long-press and drag a card onto another to reorder, like moving '
        'home-screen icons, without opening Settings.',
  ),
  ChangelogEntry(
    version: 'v1.4.32 beta',
    date: '2026-08-12',
    noteTr:
        'Maks./Min. irtifa etiketleri taşıyordu ("Maksimum ..." gibi '
        'kesiliyordu) - kısaltıldı ve kart yazı boyutu küçültüldü. Kayıt '
        'ekranındaki "Toplam süre" yazısı kaldırıldı, sadece ikon+süre kaldı. '
        'Oto-duraklama artık 3 saniye durunca devreye giriyor (önceden 15 '
        'saniyeydi) - bu sadece görsel "bekleniyor" rozeti, mola sayımını (10 '
        'dakika eşiği) etkilemiyor. Ayarlar\'a yeni bir ekran eklendi: "Kayıt '
        'ekranı kartları" - kayıt ekranının canlı bilgi sayfasındaki kartları '
        '(sürüş süresi, mesafe, irtifa, hız vb.) sürükleyip istediğiniz '
        'sıraya koyabilir, istemediklerinizi anahtarla kapatabilirsiniz.',
    noteEn:
        'Max./Min. altitude labels were overflowing — shortened, card type '
        'smaller. “Total duration” text on the recording screen removed '
        '(icon+time only). Auto-pause engages after 3 s still (was 15 s) — '
        'visual badge only, rest counting still uses the 10 min threshold. '
        'Settings → “Recording screen cards” lets you drag-reorder and hide '
        'live cards.',
  ),
  ChangelogEntry(
    version: 'v1.4.31 beta',
    date: '2026-08-12',
    noteTr:
        'Kayıt ekranı canlı bilgi sayfasında aktif sürüş süresi artık '
        'mesafenin hemen yanında (Günlük sekmesindeki süre+km eşleşmesiyle '
        'aynı mantık) - mola süresi de yükseklikle eşleşti. Harita '
        'sayfasındaki küçük hız kutusu belirgin şekilde büyütüldü.',
    noteEn:
        'On the live info page, active riding time sits next to distance '
        '(same pairing as the Daily tab’s time+km); rest duration pairs with '
        'elevation. The small map-page speed box is much larger.',
  ),
  ChangelogEntry(
    version: 'v1.4.30 beta',
    date: '2026-08-12',
    noteTr:
        'KRİTİK CI düzeltmesi (3. adım): Gradle ve AGP\'den sonra bu sefer de '
        'Kotlin sürümü (2.1.20) Flutter\'ın yeni minimum gereksinimini '
        '(2.2.20) karşılamıyordu. Kotlin 2.2.20\'ye yükseltildi - hâlâ AGP '
        '9\'un altında kalınıyor (file_picker gibi eklentilerin Kotlin '
        'derlemesini bozmaması için). Uygulama tarafında görünür bir '
        'değişiklik yok.',
    noteEn:
        'Critical CI fix (step 3): after Gradle and AGP, Kotlin 2.1.20 was '
        'below Flutter’s new minimum (2.2.20). Kotlin raised to 2.2.20, still '
        'under AGP 9 so plugins like file_picker keep compiling. No visible '
        'product change.',
  ),
  ChangelogEntry(
    version: 'v1.4.29 beta',
    date: '2026-08-12',
    noteTr:
        'KRİTİK CI düzeltmesi (devam): bir önceki Gradle yükseltmesi tek '
        'başına yetmedi - Flutter bu sefer de Android Gradle Plugin sürümünün '
        '(8.11.0) en az 8.11.1 olmasını istedi. AGP 8.11.1\'e yükseltildi '
        '(hâlâ 9\'un altında - file_picker gibi bazı eklentilerin Kotlin '
        'derlemesini bozmaması için AGP 9+\'a geçilmiyor). Uygulama tarafında '
        'görünür bir değişiklik yok.',
    noteEn:
        'Critical CI fix (continued): Flutter then required Android Gradle '
        'Plugin ≥ 8.11.1 (was 8.11.0). AGP 8.11.1, still below 9 so '
        'file_picker and similar plugins keep compiling. No visible product '
        'change.',
  ),
  ChangelogEntry(
    version: 'v1.4.28 beta',
    date: '2026-08-12',
    noteTr:
        'Kayıt ekranındaki en üstteki "Toplam süre" şeridi (ikon+etiket+rakam '
        'hepsi tek satırda) dengesiz duruyordu - artık ikon+etiket üstte, '
        'büyük süre rakamı hemen altında ortalanmış. Ayrıca: Günlük '
        'sekmesindeki gün ayrımının zaten takvim günü (gece yarısı) sınırına '
        'göre otomatik olduğu doğrulandı - ek bir değişiklik gerekmedi.',
    noteEn:
        'The top “Total duration” strip (icon+label+number on one line) '
        'looked unbalanced — icon+label on top, large time centered under it. '
        'Daily-tab day splits already use calendar midnight; no extra change '
        'needed.',
  ),
  ChangelogEntry(
    version: 'v1.4.27 beta',
    date: '2026-08-12',
    noteTr:
        'KRİTİK CI düzeltmesi: bir önceki push\'ta Android APK derlemesi '
        'başarısız oldu - CI\'daki Flutter "stable" kanalı kendiliğinden yeni '
        'bir sürüme geçmiş ve artık en az Gradle 8.14.0 istiyor, projeyse '
        '8.13\'e sabitliydi. android/gradle/wrapper/gradle-wrapper.properties '
        '8.14\'e yükseltildi. Uygulama tarafında görünür bir değişiklik yok.',
    noteEn:
        'Critical CI fix: the previous push’s Android APK failed because CI '
        'Flutter stable now wants Gradle ≥ 8.14.0 and the project was pinned '
        'to 8.13. gradle-wrapper.properties raised to 8.14. No visible '
        'product change.',
  ),
  ChangelogEntry(
    version: 'v1.4.26 beta',
    date: '2026-08-12',
    noteTr:
        'Bir önceki sürümde "ikon rengi/büyüklüğü" ayarı yanlışlıkla sadece '
        'istatistik kartı ikonlarına eklenmişti - kullanıcı aslında harita '
        'üzerindeki araç ikonunu (motor/araba işaretçisi) kastetmişti. Araç '
        'ikonu seçim ekranı de aynı mantığa geçti: araç türü (klasik '
        'nokta/motosiklet/araba), renk ve büyüklük artık üç ayrı, birbirinden '
        'bağımsız seçim - önceden bunlar 10 sabit kombinasyondan biri olarak '
        'seçilebiliyordu (ör. "seçenek 3" hem belirli bir rengi hem belirli '
        'bir boyu birlikte getiriyordu), artık istediğin rengi istediğin '
        'boyla eşleştirebilirsin.',
    noteEn:
        'The previous “icon color/size” setting only hit stat-card icons — '
        'the request was the map vehicle marker. The vehicle picker now has '
        'independent type (classic/motorcycle/car), color and size instead of '
        '10 fixed combos.',
  ),
  ChangelogEntry(
    version: 'v1.4.25 beta',
    date: '2026-08-12',
    noteTr:
        'Analiz paneli ve kayıt bilgi sayfasında bir dizi düzen düzeltmesi: '
        '(1) Özet sekmesinin en üstteki 3\'lü şeridi ("Mesafe/Aktif sürüş '
        'süresi/Maks. hız") uzun etiket yüzünden dengesiz görünüyordu - Maks. '
        'hız yerine Ortalama hız kondu, sürüş süresi sütununa daha fazla yer '
        'ayrıldı. (2) Aynı sekmenin Zaman grid\'inde: Ortalama hız\'ın yanına '
        'Maks. hız eklendi, Maksimum/Minimum irtifa satırı Tırmanış/İniş\'in '
        'üstüne taşındı, Pil kutusu grid\'den çıkarılıp ayrı, ortalanmış bir '
        'satır oldu. (3) Yükseklik sekmesinin en altına büyük punto ile "Son '
        'irtifa" eklendi. (4) Kayıt ekranının canlı bilgi sayfasında: '
        'Maksimum/Minimum irtifa yukarı, Tırmanış/İniş aşağı taşındı, '
        'Ortalama hız\'ın yanına Maks. hız geldi, Son moladan bu yana kendi '
        'satırına geçti. (5) Günlük sekmesinde sürüş süresi artık mesafeden '
        'önce (yan yana kalıyor). (6) Canlı harita üstündeki '
        'Süre/Mesafe/Yükseklik kutularının değerleri artık etiketlerinin '
        'yanında değil altında, ortalanmış.',
    noteEn:
        'Analysis and recording-info layout: (1) Overview top trio uses '
        'Average speed instead of Max so riding time has more room. (2) Time '
        'grid: Max next to Average, Max/Min altitude above Climb/Descent, '
        'Battery on its own centered row. (3) Elevation tab ends with a large '
        '“Last altitude”. (4) Live info: Max/Min altitude up, Climb/Descent '
        'down, Max next to Average, Since last rest on its own row. (5) Daily '
        'tab shows riding time before distance. (6) Live map '
        'Duration/Distance/Elevation values sit under their labels, centered.',
  ),
  ChangelogEntry(
    version: 'v1.4.24 beta',
    date: '2026-08-12',
    noteTr:
        'v1.4.23\'te Analiz panelinin Özet sekmesine eklenen "Son moladan bu '
        'yana" kartı kaldırıldı - kaydedilmiş/içe aktarılmış bir rota için '
        '"şu ana kadar" gibi bir zaman kavramı anlamsız, bu ancak canlı, '
        'devam eden bir kayıt için mantıklı bir bilgi. Kayıt ekranının bilgi '
        'sayfasında (canlı) olduğu gibi duruyor.',
    noteEn:
        'The “Since last rest” card added to Analysis → Overview in v1.4.23 '
        'is gone — “until now” is meaningless on a saved/imported route. It '
        'stays on the live recording info page.',
  ),
  ChangelogEntry(
    version: 'v1.4.23 beta',
    date: '2026-08-12',
    noteTr:
        'Kayıtlı/yüklenmiş rotalar için ayrı bir tam ekran "özet" sayfası '
        '(mavi kartlı) eklenmişti (v1.4.19), ama zaten var olan Analiz '
        'panelinin Özet sekmesiyle neredeyse aynı bilgileri gösteriyordu - '
        'aynı rota için iki ayrı özet ekranı olması kafa karıştırıcıydı. Ayrı '
        'mavi sayfa tamamen kaldırıldı; onda olup Analiz panelinde olmayan '
        'bilgiler (tırmanış, iniş, son moladan bu yana geçen süre) Analiz '
        'panelinin Özet sekmesine eklendi. Artık rota istatistikleri için tek '
        'bir yer var.',
    noteEn:
        'The extra full-screen blue “summary” page (v1.4.19) duplicated '
        'Analysis → Overview. It is removed; climb, descent and time since '
        'last rest moved onto Overview. Route stats live in one place.',
  ),
  ChangelogEntry(
    version: 'v1.4.22 beta',
    date: '2026-08-12',
    noteTr:
        'Özet sayfalarındaki (hem canlı kayıt hem kayıtlı rota) '
        'tırmanış/iniş/maksimum irtifa/minimum irtifa kartları tek satırda '
        '4\'lü gösteriliyordu, çok sıkışık duruyordu. Artık iki satıra '
        'bölündü: tırmanış ve iniş bir satırda, maksimum ve minimum irtifa '
        'hemen altındaki satırda.',
    noteEn:
        'Climb/descent/max/min altitude cards on summary pages were a cramped '
        'row of four. Now two rows: climb+descent, then max+min altitude.',
  ),
  ChangelogEntry(
    version: 'v1.4.21 beta',
    date: '2026-08-12',
    noteTr:
        'Bir seferde birçok küçük düzeltme: (1) Uygulama açılışında yarım '
        'kalmış kayıtları otomatik "kurtarıp" rota listesine ekleyen özellik '
        'kaldırıldı - anlık aksaklıklarda ortaya çıkan sahte kayıtlarla '
        'listeyi karıştırıyordu, artık böyle bir kalıntı sessizce siliniyor. '
        '(2) Mola tanımı değişti: artık sadece 10 dakika ve üzeri süren '
        'duruşlar "mola" sayılıyor - kısa bir kırmızı ışık/duraklama artık '
        'sürüş süresine dahil kalıyor, mola süresini şişirmiyor (hem canlı '
        'kayıtta hem kayıtlı rota özetinde). (3) "Ortalama hız" artık '
        'gerçekten sadece sürüş süresi üzerinden (mesafe ÷ hareket hâlindeki '
        'süre) hesaplanıyor. (4) Kayıt ekranındaki canlı haritanın üstündeki '
        'Süre/Mesafe/Yükseklik kutuları artık hız rakamının kendi satırında '
        'değil, altında ayrı bir satırda - hız 3 haneye çıkınca artık o '
        'kutuları sıkıştırıp okunmaz hâle getirmiyor. (5) Ayarlar\'a yeni bir '
        '"İstatistik ikon görünümü" eklendi: kart ikonlarının rengini ve '
        'büyüklüğünü istediğin gibi seçebiliyorsun. (6) Hem canlı kayıt hem '
        'kayıtlı rota özet sayfalarında: "Toplam süre" şeridi kaldırıldı '
        '(Sürüş süresi + Mola süresi zaten yeterli), "Maks. hız" kartının '
        'yanına "Son moladan bu yana" geçen süre eklendi, '
        'tırmanış/iniş/maksimum irtifa/minimum irtifa artık tek satırda yan '
        'yana - hepsi aynı irtifa profiline ait oldukları için birlikte '
        'okunuyor.',
    noteEn:
        'Several small fixes: (1) Auto-recovering half-finished recordings '
        'into the list is gone — glitches created junk rides; leftovers are '
        'deleted quietly. (2) A rest is 10+ minutes; short lights stay in '
        'riding time. (3) Average speed is distance ÷ moving time. (4) Live '
        'map Duration/Distance/Elevation sit on their own row under speed so '
        '3-digit speeds do not crush them. (5) Settings → “Stat icon look” '
        'for card icon color and size. (6) Summary pages: Total strip removed '
        '(Riding + Rest is enough), “Since last rest” next to Max speed, '
        'climb/descent/max/min altitude on one row.',
  ),
  ChangelogEntry(
    version: 'v1.4.20 beta',
    date: '2026-08-12',
    noteTr:
        'GPS hız/yön gecikmesine farklı bir çözüm denendi: bir telefonun GPS '
        'çipi zaten gerçekçi olarak saniyede birden hızlı ölçüm üretemiyor '
        '(bir önceki sürümde aralık zaten bu tavana çekilmişti), yani aralığı '
        'daha da kısaltmanın faydası yok - asıl sorun her yeni ölçüm gelene '
        'kadar rakamın/haritanın olduğu yerde donup sonra bir anda zıplaması. '
        'Artık hız rakamı (hem kayıt hem bilgi sayfasında) ve harita kamerası '
        '(konum + yön birlikte) her yeni ölçümde hedefe doğru sürekli, akıcı '
        'bir animasyonla kayıyor - veri gerçekte hâlâ ~1 saniyede bir gelse '
        'de ekran hiç durağan görünmüyor, sürekli canlı/hareket hâlinde '
        'hissettiriyor.',
    noteEn:
        'GPS speed/heading still arrive about once a second; the number and '
        'map camera now ease toward each new fix so the screen never looks '
        'frozen between updates.',
  ),
  ChangelogEntry(
    version: 'v1.4.19 beta',
    date: '2026-08-12',
    noteTr:
        'Kayıtlı/yüklenmiş rotalar için de kayıt ekranının bilgi sayfasına '
        'benzer bir "özet" sayfası eklendi (harita ekranındaki yeni ikonla '
        'geçiliyor): en üstte büyük bir "Toplam süre" şeridi, altında sürüş '
        'süresi/mola süresi çifti, ardından mesafe, ortalama hız, maks. hız, '
        'tırmanış, iniş, maksimum irtifa ve minimum irtifa - hepsi aynı mavi '
        'kart tasarımıyla. Ayrıca kayıt ekranının bilgi sayfasındaki, küçük '
        'olduğu için okunması güç hız/yükseklik mini grafikleri kaldırıldı; '
        'yerlerine maksimum irtifa ve minimum irtifa kutuları eklendi.',
    noteEn:
        'Saved/imported routes get a summary page like recording info (new '
        'map icon): large Total duration, riding/rest pair, then distance, '
        'average/max speed, climb, descent, max/min altitude in the same blue '
        'cards. Tiny live speed/elevation mini-charts are replaced by max/min '
        'altitude boxes.',
  ),
  ChangelogEntry(
    version: 'v1.4.18 beta',
    date: '2026-08-11',
    noteTr:
        'KRİTİK düzeltme: hız göstergesi çok gecikmeli görünüyordu, harita da '
        'bazen gerçek yönle uyuşmayan bir tarafa dönmüş kalıyordu - asıl '
        'sebep, hem kayıt için kullanılan native GPS servisinin hem de '
        'haritayı döndüren konum akışının sadece 5 saniyede bir '
        'güncellenmesiydi (bir de native tarafta 2 saniyelik ek eşik vardı). '
        'İkisi de artık saniyede bir güncelleniyor (native tarafta ek eşik '
        '0.5 saniyeye indirildi) - normal bir navigasyon uygulamasının '
        'güncelleme hızına yakın. Hız artık gerçek hızlanma/yavaşlamayı çok '
        'daha yakından takip ediyor, harita da dönüşleri çok daha hızlı '
        'yakalıyor.',
    noteEn:
        'Critical: speed lagged and the map sometimes faced the wrong way '
        'because both the native GPS service and the heading stream updated '
        'only every 5 s (plus a 2 s native threshold). Both now update about '
        'once a second (native threshold 0.5 s) — closer to a normal '
        'navigation app.',
  ),
  ChangelogEntry(
    version: 'v1.4.17 beta',
    date: '2026-08-11',
    noteTr:
        'Kayıt bilgi sayfasında "Toplam süre" şeridi en az 2 kat büyütüldü - '
        'artık alttaki mavi kartların yazılarından belirgin şekilde daha '
        'büyük. Rotalar listesinde: ayarlar ikonu artık çoklu seçim modunda '
        'da görünüyor (önceden kayboluyordu); seçim araç çubuğuna "Tümünü '
        'göster" onay kutusu eklendi (işaretlenince tüm rotalar tek seferde '
        'seçilir); "Haritada göster"in yanına bir sil ikonu eklendi, seçili '
        'rotaları tek dokunuşla (onay istenerek) siler.',
    noteEn:
        'Recording-info “Total duration” strip is at least 2× larger than the '
        'blue cards. On the routes list the settings icon stays in '
        'multi-select; the toolbar has a “Show all” checkbox and a delete '
        'icon next to “Show on map” (with confirm).',
  ),
  ChangelogEntry(
    version: 'v1.4.16 beta',
    date: '2026-08-11',
    noteTr:
        'Bilgi sayfası yeniden düzenlendi: "Toplam süre" artık en üstte, '
        '"Otomatik duraklatıldı" bandının üzerinde kendi şeridinde; süre '
        'kutuları satırında toplam süre yerine artık mola süresi var (aktif '
        'sürüş süresinin yanında); "Yükseklik" kartı istatistik ızgarasında '
        'artık "Mesafe"nin hemen yanında; mavi kartlardaki ikon+yazı bloğu '
        'artık kutunun ortasında (önceden sola yaslıydı); hız/yükseklik '
        'grafiklerine ayrılan alan büyütüldü (mola süresi ve toplam süre '
        'ızgaradan çıkınca boşta kalan yer değerlendirildi). Harita '
        'sayfasında hız kutusuna biraz daha nefes alanı bırakmak için sağdaki '
        'süre/mesafe/yükseklik kutusunun yazıları azıcık küçültüldü (yine de '
        'eski halinden büyük).',
    noteEn:
        'Info page: “Total duration” is its own top strip above the '
        'auto-pause band; the time row shows rest next to active riding; '
        'Elevation sits beside Distance; blue-card icon+text is centered; '
        'speed/elevation charts use the freed space. Map-page '
        'Duration/Distance/Elevation type is slightly smaller to give the '
        'speed box room (still larger than originally).',
  ),
  ChangelogEntry(
    version: 'v1.4.15 beta',
    date: '2026-08-11',
    noteTr:
        'KRİTİK düzeltme: haritadaki araç işaretçisi hâlâ yukarı bakmıyordu - '
        'gerçek sebep, flutter_map\'in Marker bileşeninin varsayılan olarak '
        'haritayla BİRLİKTE dönmesiydi (rotate:true set edilmemişti), yani '
        'harita yön-takip için döndükçe işaretçi de onunla birlikte dönüp '
        'ekranda yanlış açıda kalıyordu. Artık işaretçi haritanın dönüşüne '
        'karşı sabitlenip her zaman yukarı bakıyor. Ayrıca: harita '
        'sayfasındaki hız/süre/mesafe/yükseklik kutularının yazıları en az 2 '
        'kat büyütüldü; bilgi sayfasındaki alt kartların değerleri artık '
        'aktif sürüş süresi kutusuyla aynı büyüklükte (gerekirse sayfa '
        'kayabilir); bilgi sayfasının rengi kırmızı ağırlıklı temadan '
        'mavi-beyaz ağırlıklı bir palete çevrildi; hız grafiğindeki sürüşün '
        'başındaki anlamsız boş bölge kaldırıldı, grafik artık gerçek '
        'hareketin başladığı noktadan başlıyor.',
    noteEn:
        'Critical: the vehicle marker still did not point up because '
        'flutter_map Markers rotate with the map by default. The marker is '
        'now counter-rotated so it always points up. Map HUD type is at least '
        '2× larger; info-page lower cards match active-time size; info '
        'palette is blue-white instead of red; the speed chart starts at real '
        'movement, not a leading empty gap.',
  ),
  ChangelogEntry(
    version: 'v1.4.14 beta',
    date: '2026-08-11',
    noteTr:
        'Bilgi sayfası baştan tasarlandı: hız rakamı çok daha büyük ve farklı '
        '(italik, kalın, parlamalı) bir fontla gösteriliyor; arka plan artık '
        'düz renk yerine hafif hareketli, modern bir gradyan+parlama efekti; '
        'önceki 7 farklı renkli kart tek bir tutarlı renge (cam görünümlü, '
        'kenarlıklı) çevrildi. Hız ve yükseklik grafiklerinde artık en yüksek '
        '(ve yükseklikte en düşük) noktalar her zaman bir nokta+etiketle '
        'sabit olarak işaretli, grafiğin ekseni zamanla yeniden ölçeklense '
        'bile pik değer görünür kalıyor. Haritaya geçiş düğmesi sol alttan '
        'sağ üste taşındı - artık iki sayfada da aynı köşede.',
    noteEn:
        'Info page redesigned: much larger italic/bold speed, a subtle moving '
        'gradient, one consistent glass card style. Speed and elevation '
        'charts always mark peak (and elevation trough) with a dot+label. The '
        'map toggle moved from bottom-left to top-right — same corner on both '
        'pages.',
  ),
  ChangelogEntry(
    version: 'v1.4.13 beta',
    date: '2026-08-11',
    noteTr:
        'Harita sayfasının üst bilgi çubuğu istenen şablona göre düzenlendi: '
        'solda tek büyük hız kutusu, sağda süre/mesafe/yükseklik artık yan '
        'yana üç sütun değil, alt alta üç satır.',
    noteEn:
        'Map-page top HUD matches the requested template: one large speed box '
        'on the left; duration/distance/elevation stacked on the right '
        'instead of three columns.',
  ),
  ChangelogEntry(
    version: 'v1.4.12 beta',
    date: '2026-08-11',
    noteTr:
        'Düzeltme: v1.4.9\'da titremeyi gidermek için eklenen "son birkaç '
        'okumanın ortalaması" yöntemi, GPS güncellemeleri seyrek geldiğinde '
        '(~5 saniyede bir) dönemeçlerde haritanın gerçek yöne yetişmesini '
        'yavaşlatıyordu - yol dönüyor ama harita hâlâ eski yöne bakıyor gibi '
        'görünüyordu. Ortalama alma yerine artık hız filtresiyle aynı mantık '
        'kullanılıyor: gerçek bir dönüş (ne kadar keskin olursa olsun) anında '
        'uygulanıyor, sadece fiziksel olarak imkansız ani sıçramalar (tek bir '
        'kötü GPS ölçümü) göz ardı ediliyor. Ayrıca bilgi panelinden haritaya '
        'geçerken harita artık bir sonraki GPS güncellemesini beklemeden '
        'anında doğru konum/yöne senkronize ediliyor.',
    noteEn:
        'The v1.4.9 heading average lagged in corners when GPS was ~5 s apart '
        '— the road turned, the map still faced the old way. Heading now uses '
        'the same logic as the speed filter: real turns apply immediately, '
        'only impossible single-sample jumps are ignored. Switching from the '
        'info panel to the map syncs position/heading immediately, without '
        'waiting for the next fix.',
  ),
  ChangelogEntry(
    version: 'v1.4.11 beta',
    date: '2026-08-11',
    noteTr:
        'Düzeltme: GPS ara sıra tek bir kötü ölçümle fiziksel olarak imkansız '
        'bir hız sıçraması veriyordu (ör. 95 km/s seyirde aniden 200 km/s '
        'görünüp hemen eski hıza dönmesi) - hız grafiğinde ve maks. hız '
        'istatistiğinde belirgin dikenler olarak görünüyordu. Artık son kabul '
        'edilen okumaya göre saniyede ~30 km/s\'i aşan imkansız '
        'hızlanma/yavaşlamalar (gerçek bir motorun yapamayacağı kadar ani) '
        'hem canlı hız göstergesinde hem de hız grafiği/istatistik '
        'hesaplamalarında göz ardı ediliyor.',
    noteEn:
        'A single bad GPS sample could spike speed (e.g. 95 → 200 km/h and '
        'back) on the chart and max-speed stat. Accelerations/brakes over ~30 '
        'km/h per second versus the last accepted reading are ignored on the '
        'live speed, chart and stats.',
  ),
  ChangelogEntry(
    version: 'v1.4.10 beta',
    date: '2026-08-11',
    noteTr:
        'Bilgi paneli geri bildirimlere göre yeniden düzenlendi: en üstte '
        'artık büyük puntoyla anlık hız var, hemen altında aktif sürüş süresi '
        've toplam süre yan yana; onların altında renkli, daha kompakt bir '
        'istatistik ızgarası (mesafe, mola, ort./maks. hız, yükseklik, '
        'çıkış/iniş); en altta da hız ve yükseklik grafikleri yan yana - '
        'hepsi kaydırma olmadan tek ekrana sığıyor. Harita düğmesi sağ üstten '
        'sol alta taşındı.',
    noteEn:
        'Info panel from feedback: large instant speed on top, active and '
        'total time side by side, then a compact colored stat grid (distance, '
        'rest, avg/max speed, elevation, climb/descent) and side-by-side '
        'speed/elevation charts — all on one screen. Map button moved from '
        'top-right to bottom-left.',
  ),
  ChangelogEntry(
    version: 'v1.4.9 beta',
    date: '2026-08-11',
    noteTr:
        'Kayıt ekranı iki sayfaya ayrıldı: kayıt başlar başlamaz artık önce '
        'toplam süre, aktif sürüş süresi, mola süresi, ortalama/maks. hız, '
        'toplam çıkış/iniş ve hız/yükseklik grafiklerinin olduğu bir bilgi '
        'paneli açılıyor; sağ üstteki düğmeyle haritaya geçilebiliyor. Ayrıca '
        'haritanın yön-yukarı dönüşü artık sağa sola titremiyor - son birkaç '
        'GPS yönünün ortalaması alınıp yumuşak şekilde döndürülüyor '
        '(navigasyon uygulamaları gibi).',
    noteEn:
        'Recording is two pages: starting a ride opens an info panel '
        '(total/active/rest time, avg/max speed, climb/descent, '
        'speed/elevation charts); top-right goes to the map. Course-up no '
        'longer jitters — the last few GPS headings are averaged and rotated '
        'smoothly.',
  ),
  ChangelogEntry(
    version: 'v1.4.8 beta',
    date: '2026-08-11',
    noteTr:
        'v1.4.7\'nin devamı: bazı telefonlarda (özellikle MIUI gibi agresif '
        'arka plan yönetimi olanlarda) sistem, öldürdüğü kayıt servisini hiç '
        'yeniden başlatmıyor - START_STICKY yeniden başlatması hiç '
        'tetiklenmiyor, dolayısıyla önceki düzeltmenin kurtarma kodu da hiç '
        'çalışmıyordu. Veri dosyası diskte kalıyordu ama kimse onu geri '
        'okumuyordu. Artık uygulama her açılışta yarım kalmış bir kayıt olup '
        'olmadığını kontrol ediyor; varsa otomatik olarak rota listesine '
        'kaydediyor ve bildirim gösteriyor.',
    noteEn:
        'Follow-up to v1.4.7: some phones (especially aggressive MIUI) never '
        'restart a killed recording service, so START_STICKY and the recovery '
        'code never ran. The data file stayed on disk unread. Every launch '
        'now checks for a half-finished recording, saves it to the route list '
        'and shows a notification.',
  ),
  ChangelogEntry(
    version: 'v1.4.7 beta',
    date: '2026-08-11',
    noteTr:
        'KRİTİK düzeltme: çok düşük pilde (veya OEM\'in agresif pil '
        'yönetiminde) Android tüm uygulamayı öldürüp arka plandaki kayıt '
        'servisini kendi kendine yeniden başlattığında, kod bunu "yeni bir '
        'kayıt başlıyor" sanıp o ana kadar diskte biriken GPS verisini '
        'siliyordu - kayıt "durmuş" gibi görünüyor, veri de gidiyordu. Artık '
        'sistemin kendi yeniden başlatması ile gerçek bir yeni kayıt ayırt '
        'ediliyor; önceki veri silinmek yerine geri yükleniyor.',
    noteEn:
        'Critical: on very low battery (or aggressive OEM killers) Android '
        'could kill the app and restart the recording service, which treated '
        'that as a new recording and wiped the GPS buffer — the ride looked '
        '“stopped” and data was gone. System restarts are now distinguished '
        'from a real new recording and previous data is restored.',
  ),
  ChangelogEntry(
    version: 'v1.4.6 beta',
    date: '2026-08-10',
    noteTr:
        'Yeni: Android Auto\'da kayıt ekranı artık gerçek bir harita '
        'gösteriyor - telefondaki gibi yön-yukarı (course-up) dönen, kat '
        'edilen rota çizgisiyle. Karolar telefonun zaten kullandığı ücretsiz '
        'Carto kaynağından (API anahtarı gerekmiyor). Deneysel: gerçek bir '
        'araçta test edilemedi, sorun görürseniz bildirin.',
    noteEn:
        'New: Android Auto recording shows a real map — course-up like the '
        'phone, with the driven line. Tiles from the same free Carto source '
        '(no API key). Experimental: not tested in a real car; please report '
        'issues.',
  ),
  ChangelogEntry(
    version: 'v1.4.5 beta',
    date: '2026-08-10',
    noteTr:
        'Düzeltme: Android Auto uygulama listesinde RideAtlas hiç '
        'görünmüyordu. Sebebi, androidx.car.app kütüphanesinin zorunlu '
        'tuttuğu bir manifest ayarının (minCarApiLevel) eksik olmasıydı - bu '
        'olmadan Android Auto uygulamayı hatasız şekilde sessizce listeden '
        'düşürüyor. Eklendi.',
    noteEn:
        'Fix: RideAtlas never appeared in the Android Auto app list. '
        'androidx.car.app requires minCarApiLevel in the manifest; without it '
        'Auto silently drops the app. Added.',
  ),
  ChangelogEntry(
    version: 'v1.4.4 beta',
    date: '2026-08-09',
    noteTr:
        'Düzeltme: bir önceki sürümde "Aktif sürüş süresi" nokta-nokta hıza '
        'bakarak hesaplanmaya başlamıştı, ama bu Günlük sekmesindeki "Sürüş '
        'süresi"nin kullandığı (20+ dk duraklama kümeleri tespit eden) '
        'yöntemden farklıydı - aynı rota için iki sekmede farklı sayılar '
        'görünebiliyordu. Artık Özet sekmesi de Günlük sekmesiyle aynı mola '
        'tespitini kullanıyor; "Aktif sürüş süresi" ve "Mola süresi" artık '
        'her iki sekmede de tutarlı.',
    noteEn:
        '“Active riding time” had started using point-to-point speed, which '
        'disagreed with Daily “Riding time” (20+ min stop clusters). Overview '
        'now uses the same stop detection; Active riding and Rest match on '
        'both tabs.',
  ),
  ChangelogEntry(
    version: 'v1.4.3 beta',
    date: '2026-08-09',
    noteTr:
        'Önemli düzeltme: Analiz > Özet sekmesinde "Aktif sürüş süresi" bazı '
        'rotalarda "Toplam süre" ile birebir aynı çıkıyor, bu yüzden "Mola '
        'süresi" de her zaman 0 görünüyordu. Kök neden: eski hesap, sadece '
        'noktalar arasında 60 saniyeden uzun bir boşluk varsa "mola verildi" '
        'sayıyordu - ama birçok GPS cihazı/uygulaması dururken de sabit '
        'aralıklarla nokta kaydetmeye devam ediyor, bu da hiç boşluk '
        'oluşmamasına yol açıyordu. Artık her nokta çifti arasındaki gerçek '
        'hıza bakılıyor (duraklarda hız ~0 km/s), bu yüzden hangi cihazla '
        'kaydedilmiş olursa olsun doğru sonuç veriyor.',
    noteEn:
        'Important: Analysis → Overview “Active riding time” sometimes '
        'equalled Total, so Rest was always 0. The old math only counted a '
        'rest when points had a 60 s gap — many GPS devices keep logging '
        'while stopped, so no gap appeared. Each pair now uses real speed (~0 '
        'km/h when stopped), so any logger is correct.',
  ),
  ChangelogEntry(
    version: 'v1.4.2 beta',
    date: '2026-08-09',
    noteTr:
        'Rota listesinde birden fazla rota seçtiğinizde artık "Birleştir" '
        'seçeneği de var - örneğin birkaç günlük bir gezinin her günü ayrı '
        'kaydedildiyse, seçilenler kendi ilk GPS zaman damgasına göre '
        'otomatik sıralanıp (seçim sırası önemli değil) tek bir yeni rotada '
        'birleştiriliyor; yeni rota için bir isim soruluyor. Orijinal rotalar '
        'silinmiyor, sadece isimlerine "(birleştirildi)" ekleniyor; '
        'üzerlerindeki fotoğraf/videolar da yeni rotaya kopyalanıyor.',
    noteEn:
        'Selecting several routes now offers Merge — e.g. each day of a trip '
        'recorded separately. Selection is ordered by first GPS time (not tap '
        'order), you name the new route, originals stay with a “(merged)” '
        'suffix, and their photos/videos are copied.',
  ),
  ChangelogEntry(
    version: 'v1.4.1 beta',
    date: '2026-08-09',
    noteTr:
        'Analiz > Özet sekmesi sadeleştirildi: Tırmanış çıkarıldı (zaten '
        'Yükseklik sekmesinde var); yerine Ortalama hız, Minimum/Maksimum/Son '
        'irtifa ve Mola süresi (toplam süre − aktif sürüş süresi) eklendi. '
        '"Net süre" etiketi "Aktif sürüş süresi" oldu. Üstteki üç büyük '
        'değerin (mesafe, süre, hız) uzun metinlerde ortadan bölünmesine yol '
        'açan görünüm hatası düzeltildi.',
    noteEn:
        'Analysis → Overview simplified: Climb removed (already on '
        'Elevation); Average speed, Min/Max/Last altitude and Rest (total − '
        'active) added. “Net time” is now “Active riding time”. The top three '
        'big values no longer wrap mid-word on long labels.',
  ),
  ChangelogEntry(
    version: 'v1.4.0 beta',
    date: '2026-08-09',
    noteTr:
        'Sürüş sırasında çekilen fotoğraflar rotaya bağlanabiliyor: kayıt '
        'bitirilip kaydedildiğinde, o sürüş süresince telefonun galerisine '
        'eklenmiş fotoğraf/videolar varsa bunlar listelenir, hangilerinin '
        'rotaya ekleneceğini seçebilirsiniz. Konumu bilinmeyen bir foto/video '
        'seçilirse, haritadan elle nereye ait olduğunu işaretlemeniz istenir. '
        'Rota haritasına, fotoğraf/video konumlarını gösterme veya gizleme '
        'için yeni bir düğme eklendi (varsayılan: gösteriliyor); '
        'gösterildiğinde her biri haritada küçük bir önizlemeyle işaretlenir '
        've dokununca tam ekran açılır. Fotoğraf/video daha sonra da elle '
        'eklenebilir - bu zaten var olan özellik değişmedi.',
    noteEn:
        'Photos taken during a ride can attach to the route: after save, '
        'gallery photos/videos from that session are listed for you to pick. '
        'Media without a location can be placed on the map by hand. A new map '
        'button shows/hides photo pins (default on); tap a pin for full '
        'screen. Manual add later is unchanged.',
  ),
  ChangelogEntry(
    version: 'v1.3.48 beta',
    date: '2026-08-09',
    noteTr:
        'Kayıt ekranındaki harita artık her zaman yön-takip (course-up) '
        'modunda - kuzey-sabit moda geçiş kaldırıldı, konum tuşu artık her '
        'basışta sadece ortalıyor. Üstteki süre/mesafe/yükseklik kutusu '
        'yeniden düzenlendi: değerler dar ekranlarda birbirine karışıp taşmak '
        'yerine, aralarında ince bir ayraçla, kendi sütunlarında okunaklı '
        'şekilde gösteriliyor.',
    noteEn:
        'The recording map is always course-up — north-up toggle removed; the '
        'location button only recenters. The top duration/distance/elevation '
        'box uses thin separators and its own columns so values no longer '
        'collide on narrow screens.',
  ),
  ChangelogEntry(
    version: 'v1.3.47 beta',
    date: '2026-08-09',
    noteTr:
        'Ekran kapalı / uyku modunda GPS kaydının kesilmesine kök çözüm: '
        'konum artık Flutter/geolocator akışı yerine Android native '
        'foreground serviste toplanıyor (Fused Location + wake lock + kalıcı '
        'bildirim). Flutter motoru Doze ile donsa bile noktalar native '
        'tampona yazılıyor; kayıt bitince rota bundan üretiliyor.',
    noteEn:
        'Root fix for GPS cutting out with the screen off: location is '
        'collected in an Android native foreground service (Fused Location + '
        'wake lock + persistent notification) instead of Flutter/geolocator. '
        'Points go to a native buffer even if the Flutter engine freezes in '
        'Doze; the route is built from that on finish.',
  ),
  ChangelogEntry(
    version: 'v1.3.46 beta',
    date: '2026-08-09',
    noteTr:
        'Arka planda / ekran kilitliyken GPS kaydının kesilmesi için önemli '
        'düzeltme: eski LocationManager yolu modern Android\'de ekran '
        'kapanınca ~60 sn içinde GPS\'i durdurabiliyordu; kayıt artık Fused '
        'Location + kalıcı bildirim + 5 sn aralıklı güncelleme kullanıyor. '
        '"Her zaman izin ver" yoksa kayıt başlamıyor (Ayarlar\'a yönlendirir); '
        'pil muafiyeti de kayıttan önce isteniyor.',
    noteEn:
        'Background / lock-screen GPS drop: the old LocationManager path '
        'could stop GPS ~60 s after the screen off. Recording now uses Fused '
        'Location + a persistent notification + 5 s updates. Recording will '
        'not start without “Allow all the time” (opens Settings); battery '
        'exemption is requested first.',
  ),
  ChangelogEntry(
    version: 'v1.3.45 beta',
    date: '2026-08-08',
    noteTr:
        'Kayıt ekranındaki harita artık normal navigasyon uygulamaları gibi '
        'varsayılan olarak yön-takip (course-up) modunda açılıyor - harita, '
        'gidilen yöne göre dönüyor. Konum tuşuna basarak kuzey-sabit moda '
        'geçilebiliyor; hangi mod seçiliyse bir sonraki kayıtta da o '
        'hatırlanıyor.',
    noteEn:
        'The recording map opens course-up like a normal navigation app. The '
        'location button switches to north-up; the chosen mode is remembered '
        'for the next recording.',
  ),
  ChangelogEntry(
    version: 'v1.3.44 beta',
    date: '2026-08-05',
    noteTr:
        'Ekran kilitliyken GPS kaydının kesilmesi sorununun gerçek kök nedeni '
        'bulundu: uygulama Android\'den hiçbir zaman "her zaman" (arka planda) '
        'konum izni istemiyordu - bu yüzden telefonun Ayarlar ekranında bu '
        'seçenek hiç görünmüyordu, sadece "uygulama kullanılırken" '
        'seçilebiliyordu, pil izni/otomatik başlatma ne kadar açık olursa '
        'olsun bu durumda ekran kilitlenince konum kesiliyordu. Artık bu izin '
        'de isteniyor; kayıt başladığında hâlâ sadece "kullanılırken" izni '
        'varsa, Ayarlar\'ı açmanız için bir uyarı çıkıyor. Ayarlar ekranına da '
        '"Konum: Her zaman izin ver" kısayolu eklendi.',
    noteEn:
        'Root cause of lock-screen GPS drop: the app never asked Android for '
        '“allow all the time”, so that option never appeared in Settings — '
        'only “while using the app”, which stops location when locked no '
        'matter the battery settings. That permission is now requested; if '
        'recording starts with only “while using”, a prompt opens Settings. '
        'Settings also has a “Location: Allow all the time” shortcut.',
  ),
  ChangelogEntry(
    version: 'v1.3.43 beta',
    date: '2026-08-05',
    noteTr:
        'Ekran kilitliyken GPS kaydının kesilmesi sorunu için ek bir '
        'düzeltme: pil optimizasyonu muafiyeti ve otomatik başlatma izni '
        'verilmesine rağmen bazı telefonlarda (Xiaomi/MIUI doğrulandı) kayıt '
        'sırasında konum güncellemeleri hâlâ duruyordu - rota haritada düz '
        'bir çizgiyle "atlıyordu". Konum artık Google Play Servisleri\'nin '
        'FusedLocationProviderClient\'ı yerine Android\'in kendi GPS '
        'sağlayıcısı (LocationManager) üzerinden alınıyor; üretici pil '
        'yöneticileri genellikle Play Servisleri konumunu çok daha agresif '
        'kısıtlıyor.',
    noteEn:
        'Further lock-screen GPS fix: even with battery exemption and '
        'autostart, some phones (Xiaomi/MIUI confirmed) still stopped updates '
        '— the track jumped as a straight line. Location now uses Android’s '
        'own LocationManager instead of FusedLocationProviderClient; OEM '
        'battery managers usually throttle Play Services harder.',
  ),
  ChangelogEntry(
    version: 'v1.3.42 beta',
    date: '2026-08-05',
    noteTr:
        'Önemli düzeltme: bazı telefonlarda araç ikonunun rengi tüm ekranı '
        'kaplıyordu (harita ve Araç ikonu seçim ekranı dahil) - çalışma '
        'zamanında renklendirme yerine, her renk seçeneği artık önceden '
        'hazırlanmış ayrı bir görsel olarak geliyor, sorun kökten çözüldü. '
        'Uydu sayısı göstergesi artık bağlantı yeterliyken (4+ uydu) yeşil, '
        'azken kırmızı renkte gösteriliyor.',
    noteEn:
        'Important: on some phones the vehicle-icon color flooded the whole '
        'screen (map and picker). Runtime tinting is gone; each color is a '
        'pre-made asset. Satellite-count badge is green at 4+ satellites, red '
        'when fewer.',
  ),
  ChangelogEntry(
    version: 'v1.3.41 beta',
    date: '2026-08-05',
    noteTr:
        'Araç ve motor haritada artık emoji yerine gerçek, üstten çekilmiş '
        'araç fotoğraflarıyla gösteriliyor - her ikisi için de 5 renk ve 5 '
        'ölçek seçeneği var (Ayarlar > Araç ikonu). Ana ekrandaki kayıt '
        'tuşunun altında ve kayıt ekranında, bağlı GPS uydu sayısını gösteren '
        'küçük bir rozet eklendi; Ayarlar > "Uydu sayısını göster" ile '
        'istenirse kapatılabilir.',
    noteEn:
        'Car and motorcycle markers are real top-down photos instead of emoji '
        '— 5 colors and 5 scales each (Settings → Vehicle icon). A small '
        'connected-satellite badge sits under the home record button and on '
        'the recording screen; Settings → “Show satellite count” can hide it.',
  ),
  ChangelogEntry(
    version: 'v1.3.40 beta',
    date: '2026-08-05',
    noteTr:
        'Önemli düzeltme: bazı telefon üreticilerinin (Xiaomi/MIUI, '
        'Oppo/ColorOS, Samsung/OneUI gibi) ek pil kısıtlamaları yüzünden, '
        'ekran kapanınca kayıt sırasında GPS güncellemeleri duruyordu - bu '
        'foreground servis dışında, üretici bazlı ek bir kısıtlama. Artık '
        'kayıt başlarken uygulamayı pil optimizasyonundan muaf tutmanız için '
        'sistem izni isteniyor; Ayarlar > "Arka planda GPS izni" ile '
        'istediğiniz zaman tekrar açabilirsiniz.',
    noteEn:
        'Important: extra OEM battery limits (Xiaomi/MIUI, Oppo/ColorOS, '
        'Samsung/OneUI) could stop GPS updates when the screen turned off, '
        'beyond the foreground service. Recording now asks to exempt the app '
        'from battery optimization; Settings → “Background GPS permission” '
        'can open that again.',
  ),
  ChangelogEntry(
    version: 'v1.3.39 beta',
    date: '2026-08-05',
    noteTr:
        'Oto-duraklama hassasiyeti düzeltildi: artık tekil GPS sıçramaları '
        'yerine son birkaç okumanın ortalamasına göre karar veriyor, '
        'durma/kalkma eşikleri de ayrı tutuldu (titreme olmasın diye). Araç '
        've motor işaretçileri renkli rozetli, gerçek emoji görsellerine '
        'geçti. Kayıt ekranındaki konum işaretçisine, MotionX-GPS\'teki gibi '
        'GPS yönünü gösteren yarı saydam bir "yön konisi" eklendi - '
        'kuzey-sabit moddayken de yön artık görülebiliyor.',
    noteEn:
        'Auto-pause uses an average of recent readings instead of a single '
        'GPS hop, with separate stop/start thresholds to avoid flicker. '
        'Vehicle markers are colored-badge real emoji images. The recording '
        'location marker has a translucent heading cone like MotionX-GPS so '
        'direction is visible in north-up too.',
  ),
  ChangelogEntry(
    version: 'v1.3.38 beta',
    date: '2026-08-05',
    noteTr:
        'Ana ekrandaki kayıt düğmesi küçültüldü. Altında GPS durumu kısa süre '
        'görünüyor: GPS yoksa offline kayıt uyarısı, GPS gelince doğruluk '
        'bilgisiyle birlikte "hazır" mesajı (birkaç saniye sonra kaybolur, '
        'tıklanamaz).',
    noteEn:
        'Home record button is smaller. GPS status flashes under it briefly: '
        'offline-recording hint if there is no GPS, then a “ready” message '
        'with accuracy (disappears after a few seconds, not tappable).',
  ),
  ChangelogEntry(
    version: 'v1.3.37 beta',
    date: '2026-08-04',
    noteTr:
        'Önemli düzeltme: v1.3.34\'te Android Auto eklenirken MainActivity\'nin '
        'Flutter motorunu ele alış şekli değişmişti, bu da Android\'de arka '
        'planda (uygulama küçültülünce) konum alınmasını bozmuştu - geri '
        'alındı, arka plan takibi eskisi gibi çalışıyor. Kayıt ekranındaki '
        'araç ikonu artık her zaman yukarı bakıyor; kuzey-sabit moddayken de '
        'artık kendi etrafında dönmüyor.',
    noteEn:
        'Important: adding Android Auto in v1.3.34 changed how MainActivity '
        'owns the Flutter engine and broke background location when the app '
        'was minimized. Reverted; background tracking works as before. The '
        'recording vehicle icon always points up and no longer spins in place '
        'in north-up.',
  ),
  ChangelogEntry(
    version: 'v1.3.36 beta',
    date: '2026-08-04',
    noteTr:
        'REC göstergesi artık bağımsız bir kutu olarak ekranın üstünde '
        'yüzmüyor - ayarlar ikonunun hemen sağında, üst çubuktaki diğer '
        'ikonlarla aynı satırda, küçük yanıp sönen bir ikon olarak duruyor '
        '(önceden ayarlar ikonunun üstüne biniyordu). Rota haritasının üst '
        'çubuğundaki foto ekleme ikonu kaldırıldı - ekranın altındaki '
        'foto/video şeridinde zaten aynı işi yapan bir düğme var.',
    noteEn:
        'The REC indicator is no longer a floating box — it sits as a small '
        'blinking icon to the right of Settings on the same top-bar row (it '
        'used to overlap Settings). The route-map top-bar add-photo icon is '
        'gone; the bottom photo/video strip already has that action.',
  ),
  ChangelogEntry(
    version: 'v1.3.35 beta',
    date: '2026-08-04',
    noteTr:
        'Kayıt ekranındaki konum tuşu artık gerçek bir mod anahtarı: zaten '
        'ortalanmışken her basış kuzey-sabit (harita hiç dönmez, araç ikonu '
        'gittiği yönü gösterecek şekilde döner) ile yön-takip (harita '
        'gittiğiniz yöne döner, araç ikonu hep yukarı bakar) arasında geçiş '
        'yapıyor. REC göstergesi artık ekranın hemen köşesinde, tüm kutusuyla '
        'yanıp sönerek duruyor - fark edilmesi daha kolay.',
    noteEn:
        'The recording location button is a real mode switch: when already '
        'centered, each tap toggles north-up (map still, vehicle rotates) and '
        'course-up (map turns, vehicle stays up). REC blinks as a full box in '
        'the corner so it is easier to see.',
  ),
  ChangelogEntry(
    version: 'v1.3.34 beta',
    date: '2026-08-04',
    noteTr:
        'Android Auto desteği eklendi: telefonda başlatılan bir kayıt, '
        'arabanın ekranından da görülüp kontrol edilebiliyor - hız, süre, '
        'mesafe orada da gösteriliyor; duraklat/devam et ve bitir düğmeleri '
        'çalışıyor (sürüş güvenliği kuralları gereği araba ekranından isim '
        'yazılamıyor, kayıt otomatik bir isimle kaydediliyor). Telefon '
        'uygulamasının en az bir kez açılmış olması yeterli. CarPlay için '
        'Apple\'dan özel izin (entitlement) gerekiyor, henüz eklenmedi.',
    noteEn:
        'Android Auto: a recording started on the phone can be watched and '
        'controlled on the car screen — speed, time, distance; pause/resume '
        'and finish work (no naming while driving; it saves under an auto '
        'name). The phone app must have been opened at least once. CarPlay '
        'needs an Apple entitlement and is not included yet.',
  ),
  ChangelogEntry(
    version: 'v1.3.33 beta',
    date: '2026-08-04',
    noteTr:
        'Önemli düzeltme: v1.3.32\'de kayıt ekranındaki '
        'hız/süre/mesafe/yükseklik kutusu bir düzen hatası yüzünden hiç '
        'görünmüyordu - düzeltildi. REC göstergesi sağ üst köşeye taşındı, '
        'artık kırmızı yanıp sönüyor ve "REC" yazısı içeriyor. Kayıt sürerken '
        'ana ekrandaki büyük "kayıt yap" düğmesi artık gizleniyor - geri '
        'dönmek için REC göstergesine dokunun.',
    noteEn:
        'Important: v1.3.32 hid the recording speed/time/distance/elevation '
        'box due to a layout bug — fixed. REC moved to the top-right, blinks '
        'red and says “REC”. While recording, the large home record button is '
        'hidden — tap REC to return.',
  ),
  ChangelogEntry(
    version: 'v1.3.32 beta',
    date: '2026-08-04',
    noteTr:
        'Kayıt ekranı yenilendi: hız büyük punto ile öne çıkarıldı, '
        'süre/mesafe/yükseklik yanında küçük gösteriliyor, oto-duraklama '
        'rozeti büyütüldü. Geri tuşu artık kaydı durdurmuyor - kayıt arka '
        'planda sürerken ekran kenarında bir REC düğmesi beliriyor, dokununca '
        'kayıt ekranına dönülüyor. Kayıt başlarken araç ekranın ortasında '
        'başlıyor; konum tuşuna 2. kez basınca harita kuzeye dönüyor. Rota '
        'özetine net sürüş süresi, toplam süre ve pil başlangıç/bitiş yüzdesi '
        'eklendi. Ayarlar > Araç ikonu ile haritadaki "buradayım" işaretini '
        'motosiklet veya araba simgesiyle (5\'er ölçek/renk seçeneği) '
        'değiştirebilirsiniz.',
    noteEn:
        'Recording screen refreshed: large speed, smaller '
        'time/distance/elevation beside it, bigger auto-pause badge. Back no '
        'longer stops the recording — a REC button stays on the screen edge '
        'and returns you. The vehicle starts centered; a second tap on '
        'location resets north. Route overview adds net riding time, total '
        'time and start/end battery. Settings → Vehicle icon can replace the '
        '“I am here” mark with a motorcycle or car (5 scales/colors each).',
  ),
  ChangelogEntry(
    version: 'v1.3.31 beta',
    date: '2026-08-04',
    noteTr:
        'Dil ikonu yerine Ayarlar ikonu geldi; içine Dil, Yardım (tüm '
        'özelliklerin detaylı anlatımı) ve Hakkında (güncel sürüm + sürüm '
        'geçmişi) bölümleri eklendi. Ekranda dolaşan versiyon rozeti '
        'kaldırıldı.',
    noteEn:
        'The language icon is now a Settings icon with Language, Help (full '
        'feature write-up) and About (current version + history). The '
        'floating version badge is gone.',
  ),
  ChangelogEntry(
    version: 'v1.3.30 beta',
    date: '2026-08-03',
    noteTr:
        'Versiyon etiketi artık ekranın sol kenarının ortasında - '
        'fotoğraf/video şeridiyle sol alt köşede üst üste binmiyordu.',
    noteEn:
        'The version label sits mid-left on the screen so it no longer '
        'overlaps the photo/video strip in the bottom-left corner.',
  ),
  ChangelogEntry(
    version: 'v1.3.29 beta',
    date: '2026-08-03',
    noteTr:
        'Rota isminin altında artık ayın ve yılın (gün olmadan) yazdığı bir '
        'tarih gösteriliyor. Dosya adından gelen rota isimlerinin sonundaki '
        'gereksiz alt çizgi/tire gibi karakterler artık otomatik '
        'temizleniyor.',
    noteEn:
        'Under the route name, month and year are shown (no day). Trailing '
        'underscores/dashes from file-based names are stripped automatically.',
  ),
  ChangelogEntry(
    version: 'v1.3.28 beta',
    date: '2026-08-03',
    noteTr:
        'Fotoğraf/video ekleme artık tek noktadan (galeriden ikisi birden '
        'seçilebiliyor). Rota adı artık üst çubuğun altında tam genişlikte, '
        'kesilmeden gözüküyor. Mola ve geceleme işaretleri artık rota ilk '
        'açıldığında gizli - istenirse düğmeyle açılıyor.',
    noteEn:
        'Adding photos/videos is one control (gallery can pick both). The '
        'route name is full-width under the app bar, not clipped. Stop and '
        'overnight markers start hidden and can be shown with a button.',
  ),
  ChangelogEntry(
    version: 'v1.3.27 beta',
    date: '2026-08-02',
    noteTr:
        'Rotalara artık video da eklenebiliyor (kameradan veya galeriden). '
        'Fotoğraf veya videoda konum bilgisi bulunamazsa, haritada nereye ait '
        'olduğunu elle işaretleyebiliyorsunuz.',
    noteEn:
        'Routes can include video (camera or gallery). If a photo or video '
        'has no location, you can mark where it belongs on the map.',
  ),
  ChangelogEntry(
    version: 'v1.3.26 beta',
    date: '2026-08-02',
    noteTr:
        'İki düzeltme: kayda başlarken harita artık yanlış bir konuma '
        'zıplamıyor; ve "Güncelle" düğmesi artık APK\'yı indirip doğrudan '
        'kurulum ekranını açıyor (önceden sadece indiriyordu, kurmak için '
        'ayrıca dosyayı bulup açmak gerekiyordu).',
    noteEn:
        'Two fixes: starting a recording no longer jumps the map to the wrong '
        'place; Update now downloads the APK and opens the installer (it '
        'previously only downloaded, and you had to find the file).',
  ),
  ChangelogEntry(
    version: 'v1.3.25 beta',
    date: '2026-08-02',
    noteTr:
        'Kayıt ekranında haritayı elle başka bir yere sürüklediğinizde artık '
        'konumunuza geri dönmek için bir düğme çıkıyor - önceden harita her '
        'GPS güncellemesinde otomatik olarak eski yerine dönüyordu.',
    noteEn:
        'After you pan the recording map, a button appears to return to your '
        'location — the map used to snap back on every GPS update.',
  ),
  ChangelogEntry(
    version: 'v1.3.24 beta',
    date: '2026-08-02',
    noteTr:
        'Kayıt ekranı artık açılır açılmaz mevcut konumunuzu gösteriyor - '
        'önceden kayıt başlayana kadar (ve ilk GPS noktası gelene kadar) '
        'sabit bir varsayılan konumda kalıyordu.',
    noteEn:
        'The recording screen shows your current location as soon as it opens '
        '— it used to stay on a fixed default until recording started and the '
        'first GPS point arrived.',
  ),
  ChangelogEntry(
    version: 'v1.3.23 beta',
    date: '2026-08-02',
    noteTr:
        'Android uygulaması artık açılışta yeni bir sürüm olup olmadığını '
        'GitHub\'dan sessizce kontrol ediyor; varsa haritanın üstünde bir '
        '"Güncelle" düğmesi çıkıyor ve tek dokunuşla indirme sayfasını '
        'açıyor.',
    noteEn:
        'The Android app silently checks GitHub for a new version on launch; '
        'if one exists, an Update button appears above the map and one tap '
        'opens the download page.',
  ),
  ChangelogEntry(
    version: 'v1.3.22 beta',
    date: '2026-08-02',
    noteTr:
        'Android uygulamasında kayıt ekranındaki "sadece ön planda sürer" '
        'uyarısı artık yanlıştı - Android\'de arka planda da kaydettiğini '
        'doğru şekilde belirtiyor (web sürümünde uyarı hâlâ geçerli).',
    noteEn:
        'The Android recording “foreground only” warning was wrong — it now '
        'correctly says recording continues in the background (the web '
        'warning still applies).',
  ),
  ChangelogEntry(
    version: 'v1.3.21 beta',
    date: '2026-08-02',
    noteTr:
        'Rota haritasına fotoğraf ekleyebilme özelliği geldi: kameradan çekip '
        'veya galeriden seçip ekleyebilirsiniz. Konum bilgisi olan '
        'fotoğraflar haritada da küçük bir işaret olarak gösteriliyor.',
    noteEn:
        'You can add photos to a route map from the camera or gallery. Photos '
        'with location also show as a small mark on the map.',
  ),
  ChangelogEntry(
    version: 'v1.3.20 beta',
    date: '2026-08-02',
    noteTr:
        'Android tarafında kayıt artık arka planda (uygulama küçültülse bile) '
        'bir bildirimle birlikte devam edebiliyor. Web tarafı değişmedi - '
        'hâlâ sekme ön plandayken kaydediyor.',
    noteEn:
        'On Android, recording can continue in the background (even if the '
        'app is minimized) with a notification. Web is unchanged — still only '
        'while the tab is in front.',
  ),
  ChangelogEntry(
    version: 'v1.3.19 beta',
    date: '2026-08-02',
    noteTr:
        'Rota haritasına geri dönüş oku eklendi (eksikti) ve rota listesinden '
        'bir rotaya girmek artık geçmişte liste ekranını bırakmıyor - böylece '
        'geri dönmek tek dokunuşla ana ekrana ulaşıyor.',
    noteEn:
        'A back arrow was added on the route map (it was missing), and '
        'opening a route from the list no longer leaves the list in history — '
        'one back goes to Home.',
  ),
  ChangelogEntry(
    version: 'v1.3.18 beta',
    date: '2026-07-30',
    noteTr:
        'Ana ekrana büyük bir kayıt düğmesi eklendi. Kayıt sırasında artık '
        'hız ve yükseklik de üstte gösteriliyor; uzun süre dursanız kayıt '
        'otomatik olarak duraklıyor, hareket edince kendiliğinden devam '
        'ediyor.',
    noteEn:
        'A large record button on Home. While recording, speed and elevation '
        'also show at the top; staying still for a long time auto-pauses, and '
        'movement resumes it.',
  ),
  ChangelogEntry(
    version: 'v1.3.17 beta',
    date: '2026-07-30',
    noteTr:
        'Açılış haritası artık konumunuz bulunduğunda yakın plana zum '
        'yapmıyor; geniş, bölgesel bir görünümde kalıyor.',
    noteEn:
        'The launch map no longer zooms in tight when your location is found; '
        'it stays on a wide regional view.',
  ),
  ChangelogEntry(
    version: 'v1.3.16 beta',
    date: '2026-07-30',
    noteTr:
        'Uygulama artık, konumunuzu gösteren canlı bir haritayla açılıyor. '
        'Kaydettiğiniz rotalara sol üstteki liste ikonundan ulaşabilirsiniz.',
    noteEn:
        'The app now opens on a live map of your location. Saved routes are '
        'behind the top-left list icon.',
  ),
  ChangelogEntry(
    version: 'v1.3.15 beta',
    date: '2026-07-28',
    noteTr:
        'Rota listesindeki kırmızı kayıt düğmesiyle artık GPS ile canlı rota '
        'kaydı yapabilirsiniz. Not: bu, sadece sekme ön planda ve ekran '
        'açıkken çalışır - arka planda devam etmez.',
    noteEn:
        'The red record button on the route list starts a live GPS recording. '
        'Note: this only runs while the tab is in front and the screen is on '
        '— it does not continue in the background.',
  ),
  ChangelogEntry(
    version: 'v1.3.14 beta',
    date: '2026-07-28',
    noteTr:
        'Birden fazla rotayı aynı haritada gösterirken de, haritayı '
        'döndürdüğünüzde artık kuzeye dön pusulası çıkıyor.',
    noteEn:
        'Showing several routes on one map now also offers the north-up '
        'compass when you rotate the map.',
  ),
  ChangelogEntry(
    version: 'v1.3.13 beta',
    date: '2026-07-28',
    noteTr:
        'Harita ekranındaki "Rotalar" penceresine de çoklu seçim eklendi: '
        'oradan da birden fazla rotayı işaretleyip aynı haritada '
        'gösterebilirsiniz.',
    noteEn:
        'The map screen’s “Routes” sheet also has multi-select: pick several '
        'routes there and show them on the same map.',
  ),
  ChangelogEntry(
    version: 'v1.3.12 beta',
    date: '2026-07-28',
    noteTr:
        'Üst çubuktaki çoklu seçim ikonu, sadece 2+ rota varken değil, tek '
        'rota varken de artık görünüyor.',
    noteEn:
        'The app-bar multi-select icon is visible even when there is only one '
        'route, not only at 2+.',
  ),
  ChangelogEntry(
    version: 'v1.3.11 beta',
    date: '2026-07-27',
    noteTr:
        'Rota listesinde artık çoklu seçim var (üst çubuktaki seçim ikonu): '
        'birden fazla rotayı işaretleyip "Haritada göster" ile hepsini aynı '
        'haritada, farklı renklerle üst üste görebilirsiniz.',
    noteEn:
        'The route list has multi-select (app-bar icon): pick several routes '
        'and “Show on map” stacks them in different colors.',
  ),
  ChangelogEntry(
    version: 'v1.3.10 beta',
    date: '2026-07-27',
    noteTr:
        'Topografik harita katmanı artık Esri altyapısından geliyor - '
        'OpenTopoMap bazen bazı kareleri (gri kutular) hiç yüklemiyordu.',
    noteEn:
        'The topographic layer now comes from Esri — OpenTopoMap sometimes '
        'never loaded some tiles (grey boxes).',
  ),
  ChangelogEntry(
    version: 'v1.3.9 beta',
    date: '2026-07-27',
    noteTr:
        'Sol alttaki versiyon yazısına dokununca artık tüm sürüm geçmişini '
        '(hangi tarihte ne eklendiğini) gösteren bir liste açılıyor.',
    noteEn:
        'Tapping the bottom-left version label opens the full version history '
        '(what landed on which date).',
  ),
  ChangelogEntry(
    version: 'v1.3.8 beta',
    date: '2026-07-27',
    noteTr:
        'Geceleme noktaları artık gün değişiminin olduğu yere göre '
        'işaretleniyor, süre eşiğine göre değil - bu sayede hiçbir geceleme '
        'atlanmıyor.',
    noteEn:
        'Overnight stays are marked at the calendar-day change, not by a '
        'duration threshold — none are skipped.',
  ),
  ChangelogEntry(
    version: 'v1.3.7 beta',
    date: '2026-07-27',
    noteTr:
        'Haritada artık gecelemeler (4 saat+ süren duraklar) molalardan '
        'farklı bir renk ve ikonla gösteriliyor - aynı göster/gizle '
        'düğmesiyle.',
    noteEn:
        'Overnight stays (stops of 4+ hours) use a different color and icon '
        'from regular stops — same show/hide button.',
  ),
  ChangelogEntry(
    version: 'v1.3.6 beta',
    date: '2026-07-27',
    noteTr:
        'Bazen harita üzerinde yüklenmeyip gri kalan kareler artık birkaç '
        'saniye içinde otomatik olarak yeniden yükleniyor.',
    noteEn:
        'Tiles that stay grey on the map now retry automatically after a few '
        'seconds.',
  ),
  ChangelogEntry(
    version: 'v1.3.5 beta',
    date: '2026-07-27',
    noteTr:
        'Haritadaki mola noktaları artık isteğe bağlı: sağ alttaki mola '
        'düğmesiyle açıp kapatabilirsiniz.',
    noteEn:
        'Stop markers on the map are optional: toggle them with the '
        'bottom-right stop button.',
  ),
  ChangelogEntry(
    version: 'v1.3.4 beta',
    date: '2026-07-27',
    noteTr:
        'Tespit edilen molalar artık haritada turuncu bir noktayla '
        'işaretleniyor; noktaya dokununca o konuma yakınlaşılıyor.',
    noteEn:
        'Detected stops are marked with an orange dot on the map; tapping one '
        'zooms to that place.',
  ),
  ChangelogEntry(
    version: 'v1.3.3 beta',
    date: '2026-07-27',
    noteTr:
        'Haritayı iki parmakla döndürdüğünüzde artık sağ altta bir pusula '
        'düğmesi çıkıyor; ona dokununca harita kuzeye göre yeniden '
        'hizalanıyor.',
    noteEn:
        'Two-finger rotating the map now shows a bottom-right compass; tap it '
        'to realign north.',
  ),
  ChangelogEntry(
    version: 'v1.3.2 beta',
    date: '2026-07-27',
    noteTr:
        'Dil seçici artık harita ekranında da mevcut (üst çubuğun sağında, '
        'dünya simgesi). Rota listesi ekranındaki dil simgesi hâlâ orada.',
    noteEn:
        'The language picker is also on the map screen (globe on the right of '
        'the app bar). The route-list language icon is still there.',
  ),
  ChangelogEntry(
    version: 'v0.4.1 beta',
    date: '2026-07-27',
    noteTr:
        'Çok günlük rotalarda artık haritada hangi günlerin gösterileceğini '
        'seçebilirsiniz (sadece 1. gün, ya da 3. ve 7. günler gibi) - sağ '
        'alttaki filtre düğmesinden.',
    noteEn:
        'On multi-day routes you can choose which days to show on the map '
        '(only day 1, or days 3 and 7, etc.) from the bottom-right filter.',
  ),
  ChangelogEntry(
    version: 'v0.4.0 beta',
    date: '2026-07-27',
    noteTr:
        'Uygulama artık Türkçe, İngilizce ve Almanca dillerinde '
        'kullanılabiliyor. Sağ üstteki dil simgesinden dilinizi '
        'seçebilirsiniz.',
    noteEn:
        'The app is available in Turkish, English and German. Pick your '
        'language from the top-right language icon.',
  ),
  ChangelogEntry(
    version: 'v0.3.2 beta',
    date: '2026-07-27',
    noteTr:
        'Çok günlük rotalar artık haritada her gün farklı bir renkle '
        'çiziliyor. Analizde yeni "Günlük" sekmesi: her gün için mesafe, '
        'sürüş/mola süresi, maksimum irtifa, tırmanış ve o gün geçilen '
        'ülkeler.',
    noteEn:
        'Multi-day routes are drawn in a different color per day. New '
        'Analysis “Daily” tab: each day’s distance, riding/rest time, max '
        'altitude, climb and countries.',
  ),
  ChangelogEntry(
    version: 'v0.3.0 beta',
    date: '2026-07-27',
    noteTr:
        'Haritada katman seçimi eklendi: sağ alttaki katman ikonuna basarak '
        'Sokak, Sade/Siyasi, Koyu, Uydu ve Topografik harita türleri arasında '
        'geçiş yapabilirsin. Seçimin hatırlanır.',
    noteEn:
        'Map layer picker: tap the bottom-right layers icon to switch Street, '
        'Clean/Political, Dark, Satellite and Topographic. Your choice is '
        'remembered.',
  ),
  ChangelogEntry(
    version: 'v0.2.9 beta',
    date: '2026-07-27',
    noteTr:
        'İçe aktarılan rotanın ismi artık dosya adını önceliyor - GPX/KML '
        'dosyasının içine gömülü genel isimler (ör. "Track 219") artık senin '
        'verdiğin dosya adının önüne geçmiyor.',
    noteEn:
        'An imported route’s name prefers the file name — generic names '
        'embedded in the GPX/KML (e.g. “Track 219”) no longer override the '
        'name you gave the file.',
  ),
  ChangelogEntry(
    version: 'v0.2.8 beta',
    date: '2026-07-27',
    noteTr:
        'GitHub Pages derlemesinde service worker kapatıldı; eski sürüm '
        'takılı kalmasın diye. Hâlâ eski badge görürsen: site verilerini '
        'temizle veya gizli pencerede aç.',
    noteEn:
        'The GitHub Pages build disables the service worker so an old version '
        'does not stick. If you still see an old badge: clear site data or '
        'open a private window.',
  ),
  ChangelogEntry(
    version: 'v0.2.7 beta',
    date: '2026-07-27',
    noteTr:
        'KML ayrıştırıcı güçlendirildi: iç içe Folder/MultiGeometry, birden '
        'fazla LineString, gx:Track ve waypoint\'ler. run_dev_web.bat port '
        '8080\'i başlamadan önce temizler.',
    noteEn:
        'KML parser strengthened: nested Folder/MultiGeometry, several '
        'LineStrings, gx:Track and waypoints. run_dev_web.bat clears port '
        '8080 before starting.',
  ),
  ChangelogEntry(
    version: 'v0.2.4 beta',
    date: '2026-07-27',
    noteTr:
        'Web sürümü GitHub Pages üzerinde yayında: '
        'https://alid67-git.github.io/RideAtlas/ — GPX\'ler tarayıcıda '
        'saklanır (cihaz başına). Analiz sekmeleri: Özet, Yükseklik, '
        'Güzergâh, Molalar, Hava.',
    noteEn:
        'Web build is live on GitHub Pages: '
        'https://alid67-git.github.io/RideAtlas/ — GPX files stay in the '
        'browser (per device). Analysis tabs: Overview, Elevation, Route, '
        'Stops, Weather.',
  ),
  ChangelogEntry(
    version: 'v0.2.2 beta',
    date: '2026-07-27',
    noteTr:
        'GitHub Actions ile GitHub Pages\'e otomatik yayınlama eklendi - depo '
        'public yapılıp Pages açıldığında, her push sonrası site birkaç '
        'dakika içinde otomatik güncellenecek.',
    noteEn:
        'GitHub Actions publishes to GitHub Pages automatically — once the '
        'repo is public and Pages is on, each push updates the site within a '
        'few minutes.',
  ),
  ChangelogEntry(
    version: 'v0.2.1 beta',
    date: '2026-07-25',
    noteTr:
        'build_web.bat artık --pwa-strategy=none ile derliyor: Flutter\'ın '
        'service worker önbelleklemesi kapatıldı, böylece yeni bir derleme '
        'sonrası eski sürümün tarayıcıda takılı kalması sorunu çözülüyor.',
    noteEn:
        'build_web.bat now builds with --pwa-strategy=none: Flutter’s '
        'service-worker cache is off so a new build no longer leaves the old '
        'version stuck in the browser.',
  ),
  ChangelogEntry(
    version: 'v0.2.0 beta',
    date: '2026-07-25',
    noteTr:
        'KML desteği eklendi: artık .gpx yanında .kml dosyaları da içe '
        'aktarılabiliyor. Paylaş butonuna basınca artık GPX mi KML mi '
        'istediğin soruluyor. Haritanın ilk açılışta boş gelme sorununa '
        'yönelik ek bir düzeltme daha yapıldı.',
    noteEn:
        'KML support: .kml files import next to .gpx. Share asks GPX or KML. '
        'Extra fix for the map opening blank.',
  ),
  ChangelogEntry(
    version: 'v0.1.12 beta',
    date: '2026-07-25',
    noteTr:
        '"GPX İçe Aktar" butonu sadece rota listesi ekranında vardı; şimdi '
        'haritadaki "Rotalar" penceresine de eklendi, listeye dönmeden yeni '
        'GPX ekleyebilirsin.',
    noteEn:
        '“Import GPX” lived only on the route list; it is also on the map '
        '“Routes” sheet so you can add a GPX without going back to the list.',
  ),
  ChangelogEntry(
    version: 'v0.1.11 beta',
    date: '2026-07-25',
    noteTr:
        'build_web.bat düzeltildi: "call" eksikti, bu yüzden pub get sonrası '
        'derleme adımı hiç çalışmıyordu.',
    noteEn:
        'build_web.bat fixed: missing “call” meant the build step never ran '
        'after pub get.',
  ),
  ChangelogEntry(
    version: 'v0.1.10',
    date: '2026-07-25',
    noteTr:
        'Açılış artık çok daha hızlı: build_web.bat ile bir kez derleyip '
        'run_web.bat ile anında açabilirsin (her seferinde yeniden '
        'derlemiyor).',
    noteEn:
        'Launch is much faster: build once with build_web.bat and open '
        'instantly with run_web.bat (no rebuild every time).',
  ),
  ChangelogEntry(
    version: 'v0.1.9',
    date: '2026-07-25',
    noteTr:
        'Harita artık ilk açılışta da tam yükleniyor (önceden yakınlaştırma '
        'butonuna basmak gerekiyordu). Analiz butonu üst çubuğa taşındı. Rota '
        'değiştirme penceresinden artık yeniden adlandırma/silme de '
        'yapılabiliyor.',
    noteEn:
        'The map now fully loads on first open (you used to have to tap '
        'zoom). Analysis moved to the app bar. The switch-route sheet can '
        'also rename/delete.',
  ),
  ChangelogEntry(
    version: 'v0.1.8',
    date: '2026-07-25',
    noteTr:
        'Analiz paneli artık ortada, derli toplu bir pencere olarak açılıyor '
        '(alttan açılan panel yerine). Harita ekranındaki liste butonu da '
        'artık geçerli haritayı kapatmadan diğer rotaların listesini ortada '
        'bir pencerede açıyor.',
    noteEn:
        'The analysis panel opens as a compact centered window (not a bottom '
        'sheet). The map list button opens other routes in a centered sheet '
        'without closing the current map.',
  ),
  ChangelogEntry(
    version: 'v0.1.7',
    date: '2026-07-25',
    noteTr:
        'Haritaya yakınlaştırma/uzaklaştırma butonları eklendi. Analiz paneli '
        'küçültüldü ve min/maks irtifa artık ayrı kartlarda gösteriliyor.',
    noteEn:
        'Zoom in/out buttons on the map. Analysis panel is smaller and '
        'min/max altitude are on separate cards.',
  ),
  ChangelogEntry(
    version: 'v0.1.6',
    date: '2026-07-25',
    noteTr:
        'Harita karoları artık yükleniyor (web\'de CORS sorunu veren OSM '
        'sunucusu yerine CARTO kullanılıyor). Analiz paneli yeniden '
        'düzenlendi: büyük özet sayılar ve yükseklik grafiği artık en üstte, '
        'daha görsel.',
    noteEn:
        'Map tiles load (CARTO instead of the OSM host that hit CORS on web). '
        'Analysis panel redesigned: large summary numbers and the elevation '
        'chart on top.',
  ),
  ChangelogEntry(
    version: 'v0.1.5',
    date: '2026-07-25',
    noteTr:
        'Harita artık tüm ekranı kaplıyor (önceki sürümde üstte küçük '
        'kalıyordu). Büyük GPX dosyaları için depolama ayrıca iyileştirildi.',
    noteEn:
        'The map fills the whole screen (it used to stay small at the top). '
        'Storage improved for large GPX files.',
  ),
  ChangelogEntry(
    version: 'v0.1.4',
    date: '2026-07-25',
    noteTr:
        'Harita boyutu düzeltildi.',
    noteEn:
        'Map size fixed.',
  ),
  ChangelogEntry(
    version: 'v0.1.3',
    date: '2026-07-25',
    noteTr:
        'Hive depolama eklendi.',
    noteEn:
        'Hive storage added.',
  ),
];
