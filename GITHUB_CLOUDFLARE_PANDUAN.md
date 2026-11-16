# Koneksi GitHub dan Cloudflare Pages — Shine

**Repository tujuan:** https://github.com/ryzakka/shine

## 1. Hubungkan proyek lokal ke GitHub

1. Ekstrak ZIP dan buka folder `shine` di Android Studio.
2. Pastikan **Git for Windows** dan **Flutter SDK** terpasang serta tersedia pada `PATH`.
3. Jalankan `HUBUNGKAN_GITHUB.bat` sekali. Skrip akan menjalankan `git init` (jika diperlukan), mengatur `origin` ke `https://github.com/ryzakka/shine.git`, membuat/memilih branch `main`, membuat kerangka Android dan Web bila Flutter tersedia, melakukan commit dan push.
4. GitHub dapat meminta Anda login melalui browser atau Git Credential Manager. Jangan masukkan token ke source code.

Jika ingin manual, dari terminal **di dalam folder `shine`**:

```powershell
flutter create --platforms=android,web --org com.ryzakka --project-name shine .
flutter pub get
git init
git branch -M main
git remote add origin https://github.com/ryzakka/shine.git
git add .
git commit -m "Initial Shine Flutter project"
git push -u origin main
```

Jika remote `origin` sudah ada, periksa `git remote -v` (jangan menambah `origin` dua kali). Pastikan username/email Git telah dikonfigurasi sebelum commit.

## 2. Build Flutter Web di Android Studio dan push ke GitHub

Jalankan `BUILD_WEB_DAN_PUSH.bat` **setiap ingin menerbitkan versi web baru**.

Skrip melakukan:
- `flutter create --platforms=web ...` (melengkapi dukungan web bila belum ada)
- `flutter pub get`
- `flutter build web --release`
- menyalin hasil `build/web/` ke `deploy/` (folder ini dilacak Git)
- commit dan push ke `origin/main`

`build/` tetap **diabaikan Git** karena keluaran sementara; `deploy/` sengaja disimpan di GitHub sebagai situs statis siap tayang.

## 3. Cloudflare Pages — tanpa build Flutter ulang

Pilih **Workers & Pages → Create application → Pages → Connect to Git → GitHub → `ryzakka/shine`**.

| Setting Cloudflare Pages | Nilai |
|---|---|
| Framework preset | None |
| Production branch | `main` |
| Build command | kosong (tanpa perintah) |
| Build output directory | `deploy` |
| Root directory | default `/` (akar repository) |

Setelah push yang mencakup folder `deploy`, Cloudflare Pages mengunggah hasil build tersebut tanpa menjalankan `flutter build` lagi. Perubahan source saja tidak mengubah situs yang tayang sampai Anda membangun ulang dan push folder `deploy` terbaru.

## 4. Supabase multiplayer

Konfigurasi Supabase di source proyek Shine sebelumnya tetap dipakai. Agar dua perangkat bisa bermain online, Anda masih harus menjalankan `supabase/migrations/001_shine_mvp.sql`, mengaktifkan Anonymous Sign-In, dan menguji koneksi di dua browser. GitHub/Cloudflare **bukan pengganti Supabase**. Multiplayer daring belum dinyatakan lulus uji end-to-end.

## 5. Jika gagal

- `git: command not found` → pasang Git for Windows dan buka ulang terminal.
- `flutter: command not found` → atur PATH Flutter SDK dan restart Android Studio.
- `Author identity unknown` → `git config --global user.name "Nama Anda"` dan `git config --global user.email "email@contoh.com"`.
- `remote origin already exists` → periksa `git remote -v`; jangan timpa remote yang tidak dikenal.
- `failed to push some refs` → cek apakah remote sudah memiliki commit dari perangkat lain; lakukan `git fetch origin` dan evaluasi perbedaannya sebelum `pull` atau `push`.
- Cloudflare 404 → periksa bahwa folder `deploy` sudah punya `index.html` di GitHub dan output directory ditulis persis `deploy`.

Catatan: file ini tidak membuat koneksi langsung dari ChatGPT ke Android Studio, GitHub, atau Cloudflare. Koneksi dilakukan oleh Git pada komputer Anda saat skrip dijalankan.
