@echo off
setlocal

cd /d "%~dp0"

if not exist "build\web\index.html" (
    echo Once build_web.bat calistirman gerekiyor - henuz derlenmemis.
    pause
    exit /b 1
)

echo Onceki calisan surum kontrol ediliyor, port 8080...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr :8080 ^| findstr LISTENING') do (
    echo Eski surum kapatiliyor - PID: %%P
    taskkill /F /PID %%P >nul 2>&1
)

echo Sunucu araci hazirlaniyor...
call dart pub global activate dhttpd >nul 2>&1

echo.
echo RideAtlas baslatiliyor - hizli mod, derleme yok...
echo Bu pencereyi kapatirsan uygulama da durur.
echo.

start "" http://localhost:8080
call dart pub global run dhttpd --path build\web --port 8080

echo.
echo Uygulama durdu.
pause
