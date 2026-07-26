@echo off
setlocal

cd /d "%~dp0"

set "FLUTTER=C:\src\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" (
    echo Flutter bulunamadi: %FLUTTER%
    pause
    exit /b 1
)

echo RideAtlas gelistirme sunucusu (Chrome, sabit port 8080)...
echo Hot reload: r   ^|   Hot restart: R   ^|   Cikis: q
echo.
echo Not: Port 8080, run_web.bat ile ayni origin'i paylasir; boylece
echo yukledigin GPX'ler ikisi arasinda da kalir.
echo.

call "%FLUTTER%" run -d chrome --web-port=8080

pause
