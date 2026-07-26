@echo off
setlocal

cd /d "%~dp0"

set "FLUTTER=C:\src\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" (
    echo Flutter bulunamadi: %FLUTTER%
    pause
    exit /b 1
)

echo RideAtlas web surumu derleniyor, bu birkac dakika surebilir...
echo (Bunu her "git pull" sonrasinda bir kez calistirman yeterli.)
echo.

call "%FLUTTER%" pub get
call "%FLUTTER%" build web --release --pwa-strategy=none

echo.
echo Derleme tamamlandi. Artik run_web.bat ile hizlica acabilirsin.
pause
