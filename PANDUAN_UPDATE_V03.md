# SHINE v0.3 — Lobi, timer, dan kontrol pertandingan

Proyek Flutter/Dart untuk Android Studio, package `com.ryzakka.shine`, dengan Supabase yang sama. **Tidak perlu membuat proyek Supabase baru.**

## Pasang pembaruan tanpa kehilangan proyek yang sudah berjalan

1. **Cadangkan** proyek lokal Anda terlebih dahulu (atau commit Git yang sudah berfungsi).
2. Salin folder `lib/` dan `test/` dari paket ini ke proyek Shine Anda. Pastikan versi Anda memang berasal dari paket Shine sebelumnya: bila Anda sudah menambahkan modifikasi sendiri, **gabungkan perubahannya**, jangan menimpa seluruh folder membabi buta.
3. Buka Supabase → **SQL Editor** dan jalankan **hanya** `supabase/migrations/002_lobi_timer_akhiri.sql` pada database lama. **Jangan jalankan ulang migrasi 001** atau menghapus tabel. SQL 002 membuat lobi dan timer menjadi aktif.
4. Di Android Studio (Terminal), pada folder proyek, jalankan `flutter pub get`, lalu `flutter test`, lalu `flutter run -d chrome` untuk mengecek web secara lokal (atau perangkat Android sesuai preferensi).
5. Untuk mengunggah versi baru ke GitHub dan menerbitkan di Cloudflare Pages, jalankan `./BUILD_WEB_DAN_PUSH.bat` pada PowerShell Windows, atau `BUILD_WEB_DAN_PUSH.bat` dari CMD. Konfigurasi Cloudflare tetap **output `deploy`, build command kosong, branch `main`**.

**Urutan disarankan:** tidak ada pertandingan daring aktif, pasang SQL 002 lalu segera deploy kode Flutter baru. Aplikasi versi lama tidak mendukung lobi baru dan akan menunggu pada layar lama setelah pemain kedua bergabung.

## Perilaku versi ini

- **Beranda:** main komputer, hotseat, buat lobi daring, gabung dengan kode, atau lanjutkan lobi/duel daring sebelumnya.
- **Lobi daring:** host membagikan kode, tamu memilih 3 tokoh dan menekan Siap. Host memilih timer 20/30/45/60 detik, lalu menekan Mulai.
- **Pengatur giliran:** timestamp akhir giliran disimpan di **Supabase**. Setiap perangkat menampilkan hitungan mundur; bila waktu lewat, pemrosesan dilakukan lewat RPC server sehingga klien tidak bisa mengirim serangan yang terlambat.
- **Waktu habis:** giliran dilewati, PA dasar hangus, PA cadangan sebelumnya dipertahankan; seluruh pertahanan lawan berakhir; cooldown tokoh tim yang melewati giliran turun.
- **Keluar ke beranda:** pertandingan daring/lobi tetap ada dan dapat dibuka lagi dari menu Lobi saya.
- **Menyerah:** lawan menang (khusus pertandingan berlangsung).
- **Bubarkan:** hanya host; menghentikan permainan/lobi untuk kedua pihak tanpa pemenang.
- **Tamu keluar lobi:** slot tamu terbuka kembali sebelum pertandingan dimulai.
- **Pertandingan lokal:** timer 30 detik; menu Hentikan menghapus save lokal; kembali ke beranda mempertahankan save lokal.

## Batasan yang masih ada

- Mode online sekarang **1 vs 1** (setiap pemain mengendalikan 3 tokoh). Pembagian 1 vs 2, 2 vs 3, dan 3 vs 3 belum diimplementasikan.
- Tidak ada proses scheduler khusus yang selalu berjalan: **timeout otomatis dipicu oleh perangkat yang sedang membuka ruang**. Saat kedua perangkat offline, hitungan waktu server tetap lewat tetapi pemrosesan giliran berikutnya dilakukan saat salah satu perangkat membuka ruang kembali. Untuk benar-benar memproses tanpa perangkat online, pasang Supabase Cron/Edge Function terpisah.
- Durasi pertandingan total belum dibatasi; saat ini timer mengikat **setiap giliran**, bukan total sesi.
- Hasil deploy Flutter dan migrasi SQL perlu diuji pada akun Supabase Anda; berkas ini disiapkan tanpa akses admin database atau Flutter SDK di lingkungan pembuatannya.

## Pengujian dua perangkat

1. Laptop buat lobi → tampil kode.
2. Ponsel gabung kode → tampil lobi yang sama, belum otomatis berperang.
3. Ponsel tekan **Siap**. Laptop pilih **20 detik** → tekan **Mulai**.
4. Biarkan giliran pertama habis → harus tertulis **Waktu Tim A habis**, kini giliran B.
5. Kembali ke beranda, pilih **Lobi saya** → dapat melanjutkan duel.
6. Dari pihak tamu pilih **Menyerah** → kedua perangkat menampilkan pemenang tim A.
7. Uji lobi baru, host klik **Bubarkan** → kedua perangkat mendapatkan layar ruang dibubarkan.

Bila SQL Editor melaporkan error, **jangan jalankan migrasi 001 ulang**. Simpan pesan error dan cocokkan dengan SQL 002.
