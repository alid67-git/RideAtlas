@echo off
REM Local release APK for GoPro Remote (Android).
REM Use a non-synced path (e.g. C:\src\RideAtlas\gopro_remote).

cd /d "%~dp0"
flutter pub get
flutter build apk --release
echo.
echo APK: %~dp0build\app\outputs\flutter-apk\app-release.apk
