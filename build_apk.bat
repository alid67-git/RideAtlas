@echo off
setlocal

cd /d "%~dp0"

rem Prefer the path used by the other Windows scripts; fall back to PATH.
set "FLUTTER=C:\src\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" (
    where flutter >nul 2>&1
    if errorlevel 1 (
        echo Flutter bulunamadi.
        echo Kurulum: git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
        echo Sonra: C:\src\flutter\bin\flutter doctor
        pause
        exit /b 1
    )
    set "FLUTTER=flutter"
)

echo RideAtlas Android APK derleniyor (release)...
echo Bu birkac dakika surebilir. Telefon USB ile bagliysa sonunda kurulum da yapilabilir.
echo.

call "%FLUTTER%" pub get
if errorlevel 1 goto :fail

call "%FLUTTER%" build apk --release
if errorlevel 1 goto :fail

set "APK=%~dp0build\app\outputs\flutter-apk\app-release.apk"
echo.
echo Derleme tamamlandi:
echo   %APK%
echo.
echo Telefona kopyalayip kur, veya USB debugging aciksa:
echo   adb install -r "%APK%"
echo.
pause
exit /b 0

:fail
echo.
echo Derleme basarisiz. flutter doctor ciktisini kontrol et.
pause
exit /b 1
