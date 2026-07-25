# RideAtlas

GPX rotalarını haritada gösteren ve detaylı analiz eden bir Flutter uygulaması. Tek kod tabanından mobil (Android/iOS), web ve masaüstü (Windows/macOS/Linux) hedeflenir; ilk aşamada mobil öncelikli geliştirilmektedir.

## Özellikler

- `.gpx` dosyası içe aktarma ve cihazda saklama
- Rotayı OpenStreetMap tabanlı haritada kırmızı çizgi olarak gösterme, başlangıç/bitiş işaretçileri ve GPX waypoint'leri
- Birden fazla rota için liste ekranı (yeniden adlandırma, silme)
- Detaylı analiz paneli: mesafe, süre, ortalama hız, tırmanış/iniş, min/maks/ortalama yükseklik ve yükseklik profili grafiği
- Rotayı GPX dosyası olarak paylaşma

## Geliştirme

```bash
flutter pub get
flutter run            # bağlı bir cihaz/emülatörde çalıştırır
flutter analyze
flutter test
```

## Klasör yapısı

```
lib/
  models/         # TrackPoint, Waypoint, GpxRoute veri modelleri
  services/       # GPX ayrıştırma ve istatistik hesaplama
  repositories/   # Rotaların kalıcı depolanması (dosya + SharedPreferences)
  screens/        # Rota listesi, harita ve analiz ekranları
  widgets/        # Paylaşılan küçük bileşenler
```
