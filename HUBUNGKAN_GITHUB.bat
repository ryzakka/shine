@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "REPO=https://github.com/ryzakka/shine.git"
echo ====================================================
echo   SHINE - HUBUNGKAN KE GITHUB
 echo ====================================================
where git >nul 2>nul
if errorlevel 1 (
  echo [GAGAL] Git belum terpasang atau tidak ada di PATH.
  echo Pasang Git for Windows, lalu buka terminal Android Studio lagi.
  pause
  exit /b 1
)
if not exist "pubspec.yaml" (
  echo [GAGAL] Jalankan skrip dari folder proyek Shine.
  pause
  exit /b 1
)
if not exist ".git" (
  git init
  if errorlevel 1 goto fail
)
git remote get-url origin >nul 2>nul
if not errorlevel 1 (
  for /f "delims=" %%U in ('git remote get-url origin') do set "CURRENT_REMOTE=%%U"
  if /I not "%CURRENT_REMOTE%"=="%REPO%" (
    echo [PERHATIAN] Remote origin sudah ada: %CURRENT_REMOTE%
    echo Demi keamanan skrip tidak mengganti remote tersebut.
    echo Periksa dengan perintah: git remote -v
    pause
    exit /b 1
  )
) else (
  git remote add origin "%REPO%"
  if errorlevel 1 goto fail
)
git branch -M main
if errorlevel 1 goto fail
where flutter >nul 2>nul
if errorlevel 1 (
  echo [PERHATIAN] Flutter tidak ditemukan di PATH.
  echo Git tetap dapat dihubungkan; untuk build web gunakan Flutter SDK.
) else (
  call flutter create --platforms=android,web --org com.ryzakka --project-name shine .
  if errorlevel 1 goto fail
  call flutter pub get
  if errorlevel 1 goto fail
)
git add -A
if errorlevel 1 goto fail
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Initial Shine Flutter project"
  if errorlevel 1 (
    echo [GAGAL] Commit gagal. Pastikan identitas Git sudah diatur:
    echo   git config --global user.name "Nama Anda"
    echo   git config --global user.email "email@contoh.com"
    goto fail
  )
)
echo.
echo [INFO] Mengirim branch main ke %REPO%
git push -u origin main
if errorlevel 1 (
  echo [GAGAL] Push gagal. Login GitHub bila diminta.
  echo Jika repository tidak kosong, periksa isinya sebelum menggabungkan riwayat.
  goto fail
)
echo [BERHASIL] Proyek Shine terhubung ke GitHub.
echo Berikutnya jalankan: BUILD_WEB_DAN_PUSH.bat
pause
exit /b 0
:fail
pause
exit /b 1
