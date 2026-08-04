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
        'aynı şekilde haritada gösterilir.',
  ),
  HelpSection(
    title: 'Rota listesi ve çoklu seçim',
    body:
        'Rota listesinde her rotayı tek dokunuşla açabilir, ismini '
        'değiştirebilir veya silebilirsiniz. Sağ üstteki seçim ikonuyla '
        'birden fazla rota seçip aynı anda haritada gösterebilir, '
        'karşılaştırabilirsiniz.',
  ),
  HelpSection(
    title: 'Harita görünümü',
    body:
        'Bir rotayı açtığınızda harita üzerinde güzergâh çizilir. Sağ alttaki '
        'ikonla harita türünü (sokak, uydu, topografik, koyu, sade) '
        'değiştirebilirsiniz. Birden çok günlük rotalarda gün filtresiyle '
        'sadece belirli günleri gösterebilir, pusula ikonuyla haritayı '
        'kuzeye çevirebilirsiniz. Mola ve geceleme noktaları başlangıçta '
        'gizlidir; üst çubuktaki düğmeyle istediğiniz zaman açıp '
        'kapatabilirsiniz.',
  ),
  HelpSection(
    title: 'Detaylı analiz',
    body:
        'Harita ekranındaki grafik ikonuyla rotanın detaylı analizini '
        'açarsınız: Özet (mesafe, süre, maksimum hız), Yükseklik profili, '
        'Güzergâh (geçilen ülkeler sırasıyla), Molalar (20 dakikadan uzun '
        'duraklamalar), Hava durumu (rota boyunca günlük hava koşulları) ve '
        'Günlük (rota birden fazla güne yayılıyorsa gün gün özet).',
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
        'büyütülerek izlenebilir.',
  ),
  HelpSection(
    title: 'GPS ile canlı rota kaydı',
    body:
        'Ana ekrandaki büyük kırmızı düğmeyle canlı GPS kaydı başlatabilir, '
        'konumunuzu gerçek zamanlı olarak haritada takip edebilirsiniz. '
        'Kayıt sırasında hız ve yükseklik gibi anlık istatistikler ekranda '
        'gösterilir; istediğiniz zaman duraklatıp devam edebilir, bitirip '
        'bir isimle kaydedebilir veya tamamen silebilirsiniz. Android\'de '
        'kayıt, uygulama küçültülse bile bir bildirimle arka planda devam '
        'eder; web tarayıcısında ise kayıt sadece sekme ön plandayken ve '
        'ekran açıkken sürer.',
  ),
  HelpSection(
    title: 'Dışa aktarma',
    body:
        'Harita ekranındaki paylaş ikonuyla açık olan rotayı GPX, KML veya '
        'KMZ formatında dışa aktarabilir, başka bir uygulamayla veya '
        'kişiyle paylaşabilirsiniz.',
  ),
  HelpSection(
    title: 'Uygulama güncellemeleri',
    body:
        'Android sürümünde yeni bir güncelleme yayınlandığında ana ekranın '
        'üstünde bir bildirim çıkar; "Güncelle" düğmesine basmanız yeterli, '
        'uygulama yeni sürümü indirip doğrudan kurulum ekranını açar. Web '
        'sürümü zaten her ziyarette otomatik olarak güncel haliyle yüklenir, '
        'ayrıca bir işlem gerekmez.',
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
        'the map the same way.',
  ),
  HelpSection(
    title: 'Route list and multi-select',
    body:
        'In the route list you can open any route with a tap, rename it, '
        'or delete it. The select icon in the top right lets you pick '
        'several routes at once and show them together on the map to '
        'compare them.',
  ),
  HelpSection(
    title: 'Map view',
    body:
        'Opening a route draws its path on the map. The icon in the bottom '
        'right switches the map type (street, satellite, topographic, '
        'dark, clean). For routes spanning several days, a day filter lets '
        'you show only certain days, and the compass icon resets the map '
        'to north-up. Stop and overnight-stay markers are hidden by '
        'default - toggle them on or off any time with the button in the '
        'top bar.',
  ),
  HelpSection(
    title: 'Detailed analysis',
    body:
        'The chart icon on the map screen opens a detailed analysis of the '
        'route: Overview (distance, duration, max speed), Elevation '
        'profile, Route (countries crossed, in order), Stops (pauses '
        'longer than 20 minutes), Weather (daily conditions along the '
        'route) and Daily (a day-by-day breakdown for multi-day routes).',
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
        'screen.',
  ),
  HelpSection(
    title: 'Live GPS recording',
    body:
        'The large red button on the home screen starts a live GPS '
        'recording, tracking your position on the map in real time. While '
        'recording, live stats like speed and altitude are shown on '
        'screen; you can pause and resume at any time, finish and save '
        'the ride under a name, or discard it entirely. On Android, '
        'recording keeps running in the background with a notification '
        'even if you minimize the app; in a web browser, recording only '
        'continues while the tab is in the foreground and the screen is '
        'on.',
  ),
  HelpSection(
    title: 'Exporting',
    body:
        'The share icon on the map screen exports the open route as GPX, '
        'KML or KMZ, so you can share it with another app or another '
        'person.',
  ),
  HelpSection(
    title: 'App updates',
    body:
        'On Android, a banner appears at the top of the home screen when '
        'a new version is out - just tap "Update" and the app downloads '
        'it and opens the installer directly. The web version always '
        'loads the latest build automatically on every visit, so there\'s '
        'nothing to do there.',
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
        'Karte angezeigt.',
  ),
  HelpSection(
    title: 'Routenliste und Mehrfachauswahl',
    body:
        'In der Routenliste können Sie jede Route mit einem Tippen öffnen, '
        'umbenennen oder löschen. Mit dem Auswahlsymbol oben rechts können '
        'Sie mehrere Routen gleichzeitig auswählen und zum Vergleich '
        'zusammen auf der Karte anzeigen.',
  ),
  HelpSection(
    title: 'Kartenansicht',
    body:
        'Beim Öffnen einer Route wird die Strecke auf der Karte '
        'eingezeichnet. Mit dem Symbol unten rechts wechseln Sie den '
        'Kartentyp (Straße, Satellit, topografisch, dunkel, einfach). Bei '
        'mehrtägigen Routen können Sie mit dem Tagesfilter nur bestimmte '
        'Tage anzeigen, und das Kompasssymbol richtet die Karte wieder '
        'nach Norden aus. Pausen- und Übernachtungsmarker sind standard­mäßig '
        'ausgeblendet - schalten Sie sie jederzeit über die Schaltfläche in '
        'der oberen Leiste ein oder aus.',
  ),
  HelpSection(
    title: 'Detaillierte Analyse',
    body:
        'Das Diagrammsymbol auf dem Kartenbildschirm öffnet eine '
        'detaillierte Analyse der Route: Übersicht (Distanz, Dauer, '
        'Höchstgeschwindigkeit), Höhenprofil, Strecke (durchquerte Länder '
        'in Reihenfolge), Pausen (Stopps länger als 20 Minuten), Wetter '
        '(tägliche Bedingungen entlang der Route) und Täglich (eine '
        'Tag-für-Tag-Aufschlüsselung bei mehrtägigen Routen).',
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
        'Bildschirmrand; ein Tipp darauf öffnet sie in Vollbild.',
  ),
  HelpSection(
    title: 'Live-GPS-Aufzeichnung',
    body:
        'Die große rote Schaltfläche auf dem Startbildschirm startet eine '
        'Live-GPS-Aufzeichnung und verfolgt Ihre Position in Echtzeit auf '
        'der Karte. Während der Aufzeichnung werden Live-Werte wie '
        'Geschwindigkeit und Höhe angezeigt; Sie können jederzeit '
        'pausieren und fortsetzen, die Fahrt unter einem Namen speichern '
        'oder verwerfen. Unter Android läuft die Aufzeichnung mit einer '
        'Benachrichtigung auch im Hintergrund weiter, wenn Sie die App '
        'minimieren; im Webbrowser läuft sie nur, solange der Tab im '
        'Vordergrund und der Bildschirm an ist.',
  ),
  HelpSection(
    title: 'Exportieren',
    body:
        'Das Teilen-Symbol auf dem Kartenbildschirm exportiert die '
        'geöffnete Route als GPX, KML oder KMZ, sodass Sie sie mit einer '
        'anderen App oder Person teilen können.',
  ),
  HelpSection(
    title: 'App-Updates',
    body:
        'Unter Android erscheint ein Banner oben auf dem Startbildschirm, '
        'sobald eine neue Version verfügbar ist - tippen Sie einfach auf '
        '"Aktualisieren", und die App lädt sie herunter und öffnet direkt '
        'das Installationsprogramm. Die Web-Version lädt bei jedem Besuch '
        'automatisch die neueste Version, hier ist nichts weiter zu tun.',
  ),
  HelpSection(
    title: 'Sprache ändern',
    body:
        'Im Bereich Sprache der Einstellungen können Sie zwischen '
        'Türkisch, Englisch und Deutsch wechseln. Ihre Wahl wird '
        'gespeichert und beim nächsten Öffnen der App beibehalten.',
  ),
];
