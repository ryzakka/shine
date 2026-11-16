# SHINE v1.3 — Arena Stabil & Multiplayer Draft Bersama

**Pembaruan terbaru** mengatasi kartu/teks keluar bingkai, menambah indikator HP adaptif,
meningkatkan feedback serangan besar, dan mengubah alur online menjadi:

**Buat ruang → teman bergabung → kedua pemain memilih 3 kartu → reveal 6 kartu → bertarung.**

> **PENTING: versi ini memerlukan migrasi SQL baru.** Pada Supabase SQL Editor,
> jalankan `supabase/migrations/003_lobby_draft_reveal.sql` **setelah** dua tabel
> `shine_characters`, `shine_rooms` dan 12 fungsi Shine yang sudah terpasang.
> Jangan gunakan frontend 1.3 dengan backend 1.2, karena pembuatan lobi
> tanpa pilihan kartu akan ditolak pada backend lama.

Panduan pembaruan lengkap ada dalam `PERUBAHAN_V13.md`.

---

> **Riwayat UI/UX v1.2.0:** Perbaikan arena anti-patahan, layout responsif ponsel/tablet/desktop, indikator aksi, pembatasan lebar panel, dan uji regresi UI. Lihat [UI_UX_PERUBAHAN.md](UI_UX_PERUBAHAN.md).

# SHINE v1.2.0 — UI/UX responsif (fitur backend v0.3)

**Pembaruan lobi online, timer giliran, dan kontrol akhir pertandingan.** Baca `PANDUAN_UPDATE_V03.md` untuk migrasi Supabase yang aman dan langkah deploy.

# SHINE — Manhwa Card Battle (Flutter/Dart, versi dimainkan)

**Nama:** Shine  
**Android application ID:** `com.ryzakka.shine`  
**IDE:** Android Studio  
**Flutter:** Dart >= 3.9, `supabase_flutter: ^2.18.3`  
**Supabase project:** `kluryjachdmtslnnqmdk`

## Pilih cara bermain

### A. Main LANGSUNG, tanpa build

Paket sumber terbaru **tidak menyertakan** `play_now/Shine_Mainkan_Sekarang.html` yang disebut pada dokumentasi v0.3. Untuk menguji aplikasi tanpa membuat APK, jalankan proyek Flutter dengan `flutter run -d chrome` pada komputer yang sudah memiliki Flutter SDK. Mode melawan komputer dan dua pemain lokal tetap bisa dijalankan tanpa koneksi internet setelah dependensi dan aset tersedia.

### B. Main sebagai aplikasi Android Flutter

Syarat: Flutter SDK (Dart 3.9+), Android SDK, Android Studio dengan Flutter/Dart plugin, emulator atau Android yang sudah mengaktifkan debugging USB.

1. Ekstrak ZIP ke sebuah folder proyek, misalnya `shine`, lalu buka folder tersebut di Android Studio.
2. Jalankan `JALANKAN_DI_ANDROID_STUDIO.bat` (Windows), atau buka terminal di folder proyek dan jalankan:

   ```bash
   flutter create --platforms=android --org com.ryzakka --project-name shine .
   flutter pub get
   flutter test
   flutter run
   ```

3. Untuk membuat APK DEBUG di komputer yang terpasang Flutter SDK, jalankan `BUAT_APK_DEBUG.bat` atau `flutter build apk --debug`. Output build normal: `build/app/outputs/flutter-apk/app-debug.apk`.

**Catatan:** Paket sumber ini belum berisi file APK jadi karena tool Flutter/Android SDK tidak tersedia di lingkungan penyusunannya. Instruksi build di atas dijalankan di komputer dengan Android Studio.

### C. Multiplayer daring — dua perangkat / 1 vs 1

Mode online adalah **dua pemain**, setiap pemain memiliki dan mengendalikan tiga kartu. Lakukan konfigurasi Supabase **sekali**:

1. Buka Supabase Dashboard → project `kluryjachdmtslnnqmdk` → SQL Editor.
2. Pada proyek yang backend-nya sudah aktif, jalankan `supabase/migrations/003_lobby_draft_reveal.sql`. Paket v1.3 ini bukan paket instalasi database dari nol.
3. Buka Authentication → Providers → Anonymous Sign-Ins dan aktifkan.
4. Pastikan `shine_rooms` tercantum pada `supabase_realtime` (migrasi mencoba menambahkannya).
5. Buka Shine di dua perangkat. Pemain A membuat ruang, B bergabung, **baru setelah keduanya hadir** masing-masing memilih tiga tokoh. Server menunggu reveal selesai sebelum duel dimulai.
6. Tombol **Lanjutkan ruang online** memungkinkan kembali ke ruang milik identitas anonymous yang sama jika belum selesai.

**Batasan saat ini:** multiplayer **1 vs 2, 1 vs 3, 2 vs 2, 2 vs 3, dan 3 vs 3 belum diimplementasikan**. Fitur persetujuan swap antar pemilik pada satu tim hanya diperlukan pada format-format tersebut. Jangan menganggapnya sudah tersedia. Setiap aksi online diproses oleh RPC PostgreSQL dengan validasi user, giliran, revision, PA, skill, dan HP.

## Fitur permainan yang telah ditulis

- 26 tokoh awal menggunakan potret dari dua kolase asli pengguna.
- Semua variasi pakaian sebuah tokoh memakai satu statistik dan satu kemampuan khas aktif yang sama.
- Tim dengan 3 kartu; satu aktif dan dua cadangan.
- PA dasar `1,2,3,4,4,...`; bank PA maksimal 4; PA tersedia maksimal 8.
- Pemain mengalokasikan Serang, Bertahan, Cadangkan, serta biaya kemampuan khas.
- Pengali damage 0, 1, 2.4, 4.2, 6.4, 9, 12, 15.4, 20 untuk serangan efektif 0–8.
- Pertahanan hanya berlaku untuk giliran lawan berikutnya lalu hangus.
- Pergantian tokoh menggunakan satu giliran penuh, tanpa PA.
- Setiap tokoh memiliki satu skill aktif, cooldown berbeda, dan cooldown berkurang meski sedang menjadi cadangan.
- Lawan komputer dengan tingkat kesulitan tiga level (Flutter + browser).
- Hotseat dua pemain satu perangkat, pemilihan tiga kartu, HP, KO, kemenangan, ulang pertandingan.
- Pertandingan offline Flutter dapat dilanjutkan kembali menggunakan shared_preferences.
- Riwayat aksi, rekor vs komputer, dan pemilihan 26 karakter.
- Pembuatan kode ruang, gabung ruang, Realtime, dan daftar ruang online.

## Perlu diketahui sebelum rilis publik

- **Belum dapat diklaim telah lulus `flutter analyze`, `flutter test`, `flutter run`, atau build APK:** Flutter/Android SDK tidak terpasang di lingkungan pembuat file. Pengujian tersebut harus dijalankan di Android Studio.
- Game browser telah lolos pemeriksaan sintaks JavaScript (`node --check`) dan uji alur logika dengan simulasi Node yang mengeksekusi pembentukan pertandingan serta empat giliran pertama. Uji UI langsung pada Chromium belum selesai.
- **Supabase belum diterapkan/diuji langsung:** publishable key tidak memberi izin admin untuk memasang SQL. Username/profil permanen, AFK/timeout, reconnect penuh, dan multiplayer >2 pemain masih pekerjaan tahap berikutnya.
- Nilai HP, ATK, 26 efek skill, biaya, dan cooldown adalah **draft balancing untuk dimainkan**, belum balancing kompetitif final.
- Versi ini bukan APK Play Store siap rilis; untuk publik dibutuhkan smoke test dua perangkat, pemeriksaan keamanan, ikon aplikasi, nama tampilan, dan signing Android release.
- **Jangan** menyimpan `service_role` key, `sb_secret_*`, atau sandi database di aplikasi. Publishable key klien tetap dilindungi melalui RLS/SQL RPC.

## Struktur proyek

```text
shine/
├── lib/main.dart
├── lib/data/characters.dart
├── lib/domain/battle_rules.dart
├── lib/domain/battle_match.dart
├── lib/game/bot_player.dart
├── lib/game/saved_game.dart
├── lib/online/shine_service.dart
├── lib/ui/home_page.dart
├── lib/ui/arena_page.dart
├── lib/ui/squad_picker.dart
├── assets/portraits/              (26 kartu)
├── supabase/migrations/003_lobby_draft_reveal.sql
├── test/arena_responsive_test.dart
├── JALANKAN_DI_ANDROID_STUDIO.bat
└── BUAT_APK_DEBUG.bat
```

## Referensi mekanisme dan SDK

- https://ludia.helpshift.com/hc/en/15-jurassic-world-the-game/faq/381-action-points/
- https://ludia.helpshift.com/hc/en/15-jurassic-world-the-game/faq/382-attack-multipliers/
- https://pub.dev/packages/supabase_flutter
- https://supabase.com/docs/guides/database/functions


## GitHub + Cloudflare Pages (build di Android Studio)

Repository: https://github.com/ryzakka/shine

1. Jalankan `HUBUNGKAN_GITHUB.bat` satu kali untuk menyiapkan Git dan melakukan push pertama.
2. Jalankan `BUILD_WEB_DAN_PUSH.bat` untuk membuat `build/web`, menyalinnya ke `deploy`, dan push hasilnya.
3. Di Cloudflare Pages pilih repo `ryzakka/shine`, branch `main`, build command kosong, output `deploy`.

Baca `GITHUB_CLOUDFLARE_PANDUAN.md` untuk penjelasan lengkap.


## Riwayat pembaruan khusus UI/UX v1.2.0

Pembaruan ini hanya mengubah tampilan Flutter dan menambahkan uji regresi UI. **Catatan ini hanya berlaku pada revisi v1.2; v1.3 membutuhkan migrasi 003 di atas.** Aplikasi tetap memakai tabel dan RPC Shine yang sudah terpasang. Bila versi sebelumnya sudah memiliki perubahan lokal, gabungkan file dengan hati-hati. Instruksi lama tentang migrasi SQL v0.3 hanya relevan untuk instalasi yang belum memasang backend itu.
