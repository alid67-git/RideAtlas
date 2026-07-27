# RideAtlas

GPX/KML rotalarını haritada gösteren ve detaylı analiz eden bir Flutter uygulaması. Tek kod tabanından mobil (Android/iOS), web ve masaüstü (Windows/macOS/Linux) hedeflenir.

## Canlı web sürümü

**https://alid67-git.github.io/RideAtlas/**

Tarayıcıdan açılır; kurulum gerekmez. İçe aktardığın GPX/KML dosyaları **o cihazın tarayıcısında** saklanır (GitHub’da değil). Telefon ve bilgisayar birbirini otomatik senkron etmez.

## Özellikler

- `.gpx`, `.kml` ve `.kmz` dosyası içe aktarma ve cihazda saklama
- Rotayı haritada kırmızı çizgi olarak gösterme, başlangıç/bitiş işaretçileri ve waypoint'ler
- Birden fazla rota için liste ekranı (yeniden adlandırma, silme)
- Sekmeli analiz: mesafe, süre, yükseklik profili, geçilen ülkeler, molalar, günlük hava
- Rotayı GPX, KML veya KMZ olarak paylaşma

## Geliştirme

```bash
flutter pub get
flutter run -d chrome --web-port=8080
flutter analyze
flutter test
```

Windows’ta hızlı başlatma: `run_dev_web.bat` (Chrome, port 8080, hot reload).

Release web derlemesi: `build_web.bat` → `run_web.bat`

## GitHub Pages (ilk kurulum)

Repo ayarlarında bir kez:

1. **Settings → Pages**
2. **Build and deployment → Source:** GitHub Actions
3. `main` branch’e push olunca workflow otomatik derler ve yayınlar

## Klasör yapısı

```
lib/
  models/         # TrackPoint, Waypoint, GpxRoute veri modelleri
  services/       # GPX/KML ayrıştırma, coğrafya, hava, istatistik
  repositories/   # Rotaların kalıcı depolanması (Hive)
  screens/        # Rota listesi, harita ve analiz ekranları
  widgets/        # Paylaşılan küçük bileşenler
```
