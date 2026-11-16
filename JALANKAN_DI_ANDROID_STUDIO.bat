@echo off
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter tidak ditemukan dalam PATH. Pasang Flutter SDK dan plugin Flutter di Android Studio.
  pause
  exit /b 1
)
call flutter create --platforms=android --org com.ryzakka --project-name shine .
if errorlevel 1 goto error
call flutter pub get
if errorlevel 1 goto error
call flutter test
if errorlevel 1 goto error
call flutter run
exit /b %ERRORLEVEL%
:error
echo Terjadi error saat menyiapkan Shine. Periksa detail di atas.
pause
exit /b 1
