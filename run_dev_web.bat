@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "FLUTTER=C:\src\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" (
    echo Flutter bulunamadi: %FLUTTER%
    pause
    exit /b 1
)

echo Port 8080 temizleniyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$procIds = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique; foreach ($procId in $procIds) { Write-Host ('Kapatiliyor PID: ' + $procId); Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }"

REM Eski dart/dhttpd surecleri bazen portu tutmaya devam eder.
taskkill /F /IM dart.exe >nul 2>&1

timeout /t 2 /nobreak >nul

netstat -ano | findstr /C:":8080" | findstr LISTENING >nul 2>&1
if not errorlevel 1 (
    echo.
    echo UYARI: Port 8080 hala dolu. Gorev Yoneticisi'nden dart.exe / dhttpd kapat
    echo veya su komutu calistir:
    echo   powershell "Get-NetTCPConnection -LocalPort 8080 ^| %% { Stop-Process -Id $_.OwningProcess -Force }"
    echo.
    pause
    exit /b 1
)

echo.
echo RideAtlas gelistirme sunucusu (Chrome, sabit port 8080)...
echo Hot reload: r   ^|   Hot restart: R   ^|   Cikis: q
echo.
echo Not: Port 8080, run_web.bat ile ayni origin'i paylasir; boylece
echo yukledigin GPX'ler ikisi arasinda da kalir.
echo.

call "%FLUTTER%" run -d chrome --web-port=8080

pause
