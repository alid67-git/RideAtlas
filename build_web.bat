@echo off
setlocal

cd /d "%~dp0"

echo RideAtlas web surumu derleniyor, bu birkac dakika surebilir...
echo (Bunu her "git pull" sonrasinda bir kez calistirman yeterli.)
echo.

call flutter pub get
call flutter build web --release

echo.
echo Derleme tamamlandi. Artik run_web.bat ile hizlica acabilirsin.
pause
