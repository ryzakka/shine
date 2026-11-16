@echo off
cd /d "%~dp0"
call flutter create --platforms=android --org com.ryzakka --project-name shine .
if errorlevel 1 goto fail
call flutter pub get
if errorlevel 1 goto fail
call flutter build apk --debug
if errorlevel 1 goto fail
echo APK di build\app\outputs\flutter-apk\app-debug.apk
pause
exit /b 0
:fail
echo Build APK gagal. Periksa Flutter SDK dan Android SDK.
pause
exit /b 1
