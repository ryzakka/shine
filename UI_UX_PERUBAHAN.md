# Shine — Pembaruan UI/UX Responsif

## Yang diubah

- `lib/ui/arena_page.dart`: layout arena menggunakan panel kendali berukuran tetap. Pada ponsel panel ada di bawah; pada viewport dengan lebar >= 850 logical px dan tinggi >= 450 logical px panel berpindah ke samping kanan. Semua status—giliran sendiri, menunggu lawan, mengirim aksi, dan selesai—memakai ruang yang sama.
- Efek benturan tidak lagi menggeser seluruh Stack panggung. Goyangan dan reaksi tetap dilakukan melalui pose kartu dan efek ilustrasi pada panggung. Posisi kartu saat menyiapkan serangan tidak lagi berubah mendadak ketika animasi dimulai.
- HUD tokoh memakai versi lebih ringkas pada lebar kecil, tombol heksagon otomatis diperkecil bila diperlukan, petunjuk PA mendapat tinggi tetap, serta tombol minus tidak aktif saat bukan giliran pengguna.
- Ditambahkan pintasan keyboard 1/2/3/4, Enter, Escape untuk desktop; status tindakan terakhir di bawah panggung, informasi giliran pada panel desktop, status menunggu yang mudah dikenali, dan tombol eksekusi yang berubah teks saat memproses aksi.
- `lib/ui/home_page.dart`: beranda dua kolom untuk layar lebar, satu kolom dengan batas lebar wajar untuk ponsel/tablet kecil. Pemilih tim menampilkan daftar tokoh dan ringkasan tim berdampingan di layar lebar.
- Lobi online dibatasi lebar 760 logical px sehingga tidak membentang penuh di desktop, kode undangan diperkecil bila layar sempit.
- Hasil pertandingan dibatasi maksimal 460 logical px sehingga tidak memenuhi monitor.

## Tidak diubah

- Angka HP, ATK, skill, PA, cooldown, hasil perhitungan serangan.
- Model `LocalBattle`, `ShineService`, RPC Supabase, berkas database, dan ID tokoh.
- Paket dependensi atau aset gambar.

## Cara memeriksa

1. Pada komputer dengan Flutter SDK 3.9+ dan proyek ini, jalankan `flutter pub get`.
2. Jalankan `dart format lib/ui/arena_page.dart lib/ui/home_page.dart test/arena_responsive_test.dart`.
3. Jalankan `flutter analyze` lalu `flutter test`.
4. Jalankan `flutter run -d chrome` dan uji lebar sekitar 320, 390, 768, 900, 1200, serta 1600 logical px, termasuk mode layar pendek.
5. Uji serang, bertahan, cadangkan, skill, swap, timer habis, giliran bot, giliran pemain online, dan hasil KO. Pastikan kartu dan panggung tidak meloncat saat footer berubah status.

## Catatan pengujian

Di lingkungan penyuntingan ini Flutter dan Dart SDK tidak tersedia. Perubahan sudah diperiksa secara statis dan pengujian regresi ditambahkan, namun *build* dan pengujian visual pada perangkat belum dapat dinyatakan berhasil sampai perintah di atas dijalankan.
