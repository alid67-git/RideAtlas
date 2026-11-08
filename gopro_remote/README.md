# GoPro Remote (Android)

RideAtlas’tan **ayrı** bir Flutter Android uygulaması. GoPro **HERO10–13 Black** kameraları [Open GoPro](https://gopro.github.io/OpenGoPro/docs/) BLE API’si ile kontrol eder.

iOS ve Insta360 (X4+) sonraki adım. RideAtlas entegrasyonu bu modül oturunca yapılacak.

## Ne yapar (v0.1.1)

- Açılışta otomatik tara + en güçlü GoPro’ya bağlan (Android GATT 133 için retry)
- Kayıt **başlat / durdur** (Wi‑Fi şart değil)
- Encoding, süre, batarya durumu (status bildirimleri)
- Kamera Wi‑Fi AP aç/kapa + SSID/şifre okuma (ileride medya indirme için)

## Desteklenen kameralar

| Model | Not |
|-------|-----|
| HERO10 Black | FW ≥ 1.70 (Open GoPro) |
| HERO11 Black / Mini | FW ≥ 1.10 |
| HERO12 Black | FW ≥ 1.10 |
| HERO13 Black | FW ≥ 1.10 |

## Çalıştırma

Windows’ta senkron klasör dışında yerel klon kullan (RideAtlas ile aynı kural):

```bat
cd gopro_remote
flutter pub get
flutter run -d <android-device>
```

Release APK:

```bat
cd gopro_remote
flutter build apk --release
```

Çıktı: `gopro_remote/build/app/outputs/flutter-apk/app-release.apk`

## Kullanım

1. Kamerayı aç, Bluetooth açık olsun.
2. Uygulamada **Tara** → kamerayı seç.
3. GoPro ekranında eşleştirme isteğini onayla (ilk sefer).
4. **KAYDI BAŞLAT** / **DURDUR**.

## Mimari not

`lib/gopro/` protokol katmanı RideAtlas’a taşınabilir paket olacak şekilde tutuluyor. Kayıt kontrolü BLE üzerinden; telefonun kamera hotspot’una bağlanması bu sürümde zorunlu değil.
