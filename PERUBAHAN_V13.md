# Shine v1.3 — UI/UX & alur online

## Yang diperbaiki

- **Arena:** dua tokoh aktif selalu dihitung berdasarkan luas panggung aktual; pada lebar kurang dari 560 px kartu mengecil dan titik pusatnya memberi ruang untuk kartu cadangan. Panggung di-clip agar partikel, overlay, banner, dan kartu animasi tidak meluber ke panel lain.
- **Banner:** judul skill dan giliran hanya satu baris, `FittedBox` memperkecil teks saat ruang kurang. Teks damage mengambang diposisikan di dalam lebar panggung.
- **HP:** hijau >65%, kuning >40%, oranye >20%, merah ≤20% (KO abu-abu); HUD menampilkan angka **HP sekarang / maksimum**, warna angka sama dengan bar dan label status. Warna HP tidak dikaitkan dengan warna tim. Tokoh sekarat berpendar merah.
- **Aksi:** kartu penyerang melesat dan berputar ringan; sasaran mundur, bergetar, memiring, memendar. Serangan kuat berdasarkan besaran HP yang hilang memiliki beberapa slash tambahan dan label **SERANGAN BESAR** atau **HANTAMAN DAHSYAT**. Ini **efek visual**, bukan bonus critical acak atau perubahan aturan damage. Pemulihan, blok, dan cadangan tetap punya efek tersendiri.
- **Layar:** panel strategi samping hanya digunakan bila viewport cukup besar (≥1040×600). Layar menengah dan ponsel menggunakan panel bawah tetap, layar landscape pendek dapat digulir. Ruang panel tidak berubah antar-giliran.
- **Beranda:** petunjuk langkah online dan input kode undangan menumpuk secara vertikal di layar sempit.
- **Lobi:** tidak memerlukan kartu untuk membuat atau bergabung. Setelah dua pemain hadir, keduanya memilih tiga kartu secara independen. Kartu lawan ditampilkan tertutup sampai fase reveal, lalu keenam kartu diungkap berurutan selama sekitar 8–9 detik, disinkronkan timestamp server.

## Penting — migrasi Supabase WAJIB

1. Cadangkan tabel `shine_rooms` dan fungsi PostgreSQL Shine aktif.
2. Buka Supabase → SQL Editor (project yang saat ini dipakai Shine).
3. Jalankan **`supabase/migrations/003_lobby_draft_reveal.sql`** sekali, setelah tabel `shine_characters`, `shine_rooms`, dan RPC lama sudah ada.
4. Jalankan Flutter versi 1.3 pada kedua perangkat. **Jangan pakai klien versi 1.2 bersamaan** dengan versi ini saat menguji alur baru.
5. Buat ruang A → gabung B → pilih kartu dari kedua sisi → lihat reveal → masuk arena. Uji kembali keluar/bergabung, berakhirnya timer, dan menyerah.

Migrasi menambahkan `lobby_phase`, `host_ready`, `reveal_started_at`, mengganti RPC `shine_create_room`, `shine_join_room`, `shine_start_room`, `shine_leave_lobby`, menambah `shine_submit_lineup`, dan membatasi fungsi `shine_submit_action_core`. Ruang yang masih berstatus **waiting** akan kembali ke fase pemilihan; pertandingan **playing** tidak diubah.

**Batas keamanan:** Kartu lawan disembunyikan oleh antarmuka sampai reveal. Karena `host_cards` dan `guest_cards` masih disimpan pada baris `shine_rooms`, klien tingkat lanjut yang mempunyai akses baca langsung dapat melihatnya lebih awal. Untuk sistem draft rahasia anti-cheat yang kompetitif diperlukan tabel pilihan terpisah yang hanya dapat dibaca server/RPC pada fase reveal; versi ini belum mengimplementasikannya.

## Verifikasi yang perlu dijalankan

```bash
flutter create --platforms=android --org com.ryzakka --project-name shine .
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Jika sudah memiliki folder Android yang valid, langkah `flutter create` dapat dilewati. Uji viewport 320×568, 390×844, 740×360, 960×720, 1440×900 dan dua tab/perangkat dengan dua akun Supabase anonymous berbeda. Periksa saat animasi serang biasa, serang besar, skill panjang seperti **LANGKAH GESIT**, KO, dan kondisi HP kritis.

**Status:** pemeriksaan struktur/sintaks pembatas sederhana dan konsistensi 26 aset dilakukan pada lingkungan penyusunan. Flutter SDK, emulator, dan kredensial admin Supabase tidak tersedia, sehingga kode Dart **belum berhasil dikompilasi** dan migrasi SQL **belum dijalankan pada project Supabase**. Pengujian final harus dilakukan pada mesin pengembangan.
