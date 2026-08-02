/// Full version history, shown when the user taps the build badge.
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
