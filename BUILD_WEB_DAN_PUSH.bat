@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo ====================================================
echo   SHINE - BUILD WEB LOKAL DAN PUSH KE GITHUB
 echo ====================================================
where flutter >nul 2>nul
if errorlevel 1 (
  echo [GAGAL] Flutter SDK tidak tersedia di PATH.
  pause
  exit /b 1
)
where git >nul 2>nul
if errorlevel 1 (
  echo [GAGAL] Git belum terpasang.
  pause
  exit /b 1
)
if not exist ".git" (
  echo [GAGAL] Jalankan HUBUNGKAN_GITHUB.bat terlebih dahulu.
  pause
  exit /b 1
)
call flutter create --platforms=web --org com.ryzakka --project-name shine .
if errorlevel 1 goto fail
call flutter pub get
if errorlevel 1 goto fail
call flutter build web --release
if errorlevel 1 goto fail
if not exist "build\web\index.html" (
  echo [GAGAL] build\web\index.html tidak ditemukan.
  goto fail
)
if not exist "deploy" mkdir "deploy"
robocopy "build\web" "deploy" /MIR /NFL /NDL /NJH /NJS >nul
if errorlevel 8 (
  echo [GAGAL] Tidak dapat menyalin hasil build ke folder deploy.
  goto fail
)
git add -A
if errorlevel 1 goto fail
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Build and deploy Shine Web"
  if errorlevel 1 goto fail
) else (
  echo [INFO] Tidak ada perubahan baru untuk di-commit.
)
git push origin main
if errorlevel 1 goto fail
echo.
echo [BERHASIL] Sumber dan hasil build web sudah dikirim ke GitHub.
echo Cloudflare Pages akan mengambil konten dari folder deploy.
echo Pengaturan: Build command KOSONG, output directory = deploy, branch = main.
pause
exit /b 0
:fail
echo [GAGAL] Build atau Git push belum berhasil. Periksa pesan error di atas.
pause
exit /b 1
