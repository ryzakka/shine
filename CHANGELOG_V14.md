# Shine v1.4.0 — Beranda, ruang publik/privat, nama pemain, dan arena stabil

## Perubahan

- Beranda pembuka hanya **SHINE / MULAI / v1.4.0**. Tombol Mulai membuka menu mode bermain yang juga menampilkan nomor versi.
- Halaman **Arena Online** baru: nama pemain (disimpan lokal), buat ruang **PUBLIK** atau **PRIVAT**, beri judul ruang, lihat dan gabung daftar ruang publik, gabung kode privat, serta lanjutkan ruang sebelumnya.
- Setiap ruang tetap berkapasitas **dua pemain**, kemudian bersama-sama memilih **tiga kartu**, disusul pengungkapan enam kartu sebelum arena.
- Nama pemain terlihat di lobi dan HUD pertarungan; nama tokoh kartu tetap tampil terpisah.
- Reduksi kedipan: warna cahaya latar arena tidak lagi berganti tiap giliran, kilatan putih layar penuh diganti efek benturan di sekitar kartu sasaran, dan panel tunggu tidak lagi menggelapkan seluruh panel strategi. Aset `Portrait` menggunakan `gaplessPlayback`.
- Penguatan privasi: daftar ruang berasal dari RPC terfilter untuk ruang publik kosong; RLS membatasi pembacaan baris `shine_rooms` kepada host/tamu.

## Penting: instalasi berurutan

1. Pastikan backend Shine yang aktif sudah memiliki tabel/fungsi dasar dan **migrasi v1.3** (`003_lobby_draft_reveal.sql`).
2. **Cadangkan database** sebelum melanjutkan. Jalankan `supabase/migrations/004_public_rooms_player_names.sql` di Supabase SQL Editor.
3. Pastikan Authentication → Anonymous Sign-Ins aktif dan publication Realtime mencakup `shine_rooms`.
4. Deploy atau jalankan Flutter versi 1.4: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d chrome` (atau perangkat Android).
5. Uji dua browser atau perangkat dengan identitas berbeda: pemain A membuat ruang publik, B masuk lewat daftar, keduanya memilih, reveal, lalu duel. Ulangi dengan ruang privat yang **tidak muncul dalam daftar** dan gabung memakai kode.

## Catatan integrasi

- Migrasi `004` **tidak** menjalankan ulang migrasi `003`; nama RPC v1.4 yang baru: `shine_create_room_v14`, `shine_join_named_room_v14`, `shine_join_public_room_v14`, `shine_list_public_rooms`.
- Ruang lama tetap berstatus **private** secara default. Ruang yang statusnya sudah `playing` tidak ditimpa.
- Nama disimpan lokal menggunakan `shared_preferences` dengan key `shine_player_name`. Akun anonim Supabase yang sama masih diperlukan untuk melanjutkan ruang pribadi.
- Ruang publik ditampilkan hanya jika `waiting`, slot tamu kosong, dan fase `gathering`; daftar diperbarui setiap 12 detik atau dengan tombol segarkan.
- Persyaratan RLS ketat: penonton bukan peserta tidak dapat mengambil data pertandingan melalui tabel; daftar publik menggunakan RPC `SECURITY DEFINER` dengan kolom terbatas.
- Kebijakan ini bisa memengaruhi klien lama yang sebelumnya mengandalkan pembacaan langsung ruang bukan miliknya. Pastikan pengguna memakai frontend v1.4.

## Batas pengujian

Kode dan SQL sudah ditinjau secara statis. Lingkungan penyusunan **tidak memiliki Flutter SDK atau akses ke instance Supabase**, sehingga belum bisa menjalankan build, Flutter analyze/test, migrasi SQL nyata, atau memastikan kedipan hilang di setiap browser. Jika masih terjadi kedipan pada perangkat tertentu, rekam layar (30/60 fps) dan kirim detail browser/GPU.
