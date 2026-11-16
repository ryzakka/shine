# Shine v1.5.0 — Pemulihan sesi & sinkronisasi host/guest

## Perbaikan yang dibuat

1. **Refresh tidak lagi otomatis mengembalikan pemain ke beranda.**
   - Setelah membuat atau memasuki ruang, ID ruang, kode, dan ID pemain disimpan secara lokal.
   - Saat web/app dibuka ulang, layar pemulihan memeriksa identitas Supabase yang tersimpan, keanggotaan ruang, serta status (`waiting`/`playing`).
   - Jika memenuhi syarat, lobi, fase pengungkapan, atau arena terbuka kembali otomatis.
   - Jika koneksi internet bermasalah, tersedia `COBA LAGI` dan `KE MENU`; petunjuk sesi tidak dihapus karena masalah jaringan.
   - Tidak ada password, access token, maupun salinan state pertarungan yang disimpan dalam petunjuk sesi lokal.

2. **Pemain tamu mengikuti host saat permainan dimulai.**
   - Sinkronisasi ruang sekarang memakai Supabase Realtime **dan** pembacaan state HTTP setiap 2 detik sebagai cadangan.
   - Jika host memulai permainan pada server, status `playing` dan `state` akan diterima pemain tamu meskipun event Realtime terlewat.
   - Revisi ruang yang lebih lama dibuang supaya pembacaan HTTP tertunda tidak memundurkan keadaan arena.
   - Stream berhenti dan subscription/timer dibersihkan saat halaman ditutup.

3. **Keluar dari halaman ≠ menyerah.**
   - Tombol `Kembali ke beranda` menonaktifkan pemulihan otomatis pada refresh berikutnya, tetapi tidak menghapus keanggotaan di database.
   - Pemain dapat membuka `LANJUTKAN RUANG SAYA` untuk bergabung kembali secara manual.
   - Menyerah dan membubarkan ruang tetap tindakan server yang berbeda.

## Cara pemasangan

- **Menggantikan versi 1.4:** salin berkas dari ZIP perubahan ke proyek Flutter v1.4, atau gunakan proyek lengkap v1.5.
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter run -d chrome` atau build web dan deploy Cloudflare Pages seperti biasa.
- **Tidak memerlukan migrasi SQL baru** jika migrasi v1.3 (`003_...`) dan v1.4 (`004_...`) sudah diterapkan.
- Jangan mengganti URL/kunci proyek Supabase ketika memperbarui. Sesi anonim terikat ke Supabase dan penyimpanan browser yang sama.

## Skenario uji dua browser / dua perangkat

1. Host buat ruang; tamu gabung. Refresh kedua halaman ketika masih di lobi → keduanya kembali ke lobi yang sama.
2. Keduanya pilih tiga kartu, kunci. Pastikan kedua halaman menampilkan pengungkapan.
3. Ketika host masuk arena, pastikan tamu ikut masuk otomatis (poll cadangan maksimal sekitar dua detik ditambah waktu permintaan jaringan).
4. Saat pertandingan berjalan, refresh salah satu sisi → kembali ke giliran yang sedang aktif (tidak membuat ruang baru).
5. Coba tutup tab/reopen pada browser yang sama; pastikan sesi masih tersimpan.
6. Klik `Kembali ke beranda` → tidak otomatis masuk lagi; gunakan `LANJUTKAN RUANG SAYA` untuk kembali.
7. Uji putus internet singkat → klik `COBA LAGI` setelah koneksi pulih.
8. Gunakan browser lain atau hapus data situs: identitas anonim lama mungkin hilang, sehingga akses ke ruang lama **tidak dijamin**. Jangan menganggap kode undangan sebagai cara mengambil alih akun pemain.

## Batasan pengujian

Pemeriksaan sintaks secara statis dan isi arsip dilakukan, tetapi Flutter SDK dan Supabase aktif tidak tersedia untuk menjalankan build atau simulasi dua browser dari lingkungan penyuntingan ini. Uji dua akun sungguhan masih diperlukan sebelum distribusi publik.
