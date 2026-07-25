@echo off
setlocal

cd /d "%~dp0"

echo Onceki calisan surum kontrol ediliyor, port 8080...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr :8080 ^| findstr LISTENING') do (
    echo Eski surum kapatiliyor - PID: %%P
    taskkill /F /PID %%P >nul 2>&1
)

echo.
echo RideAtlas baslatiliyor...
echo Bu pencereyi kapatirsan uygulama da durur.
echo.

flutter run -d chrome --web-port=8080

echo.
echo Uygulama durdu.
pause
