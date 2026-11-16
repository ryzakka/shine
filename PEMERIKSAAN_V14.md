# Pemeriksaan Shine v1.4.0

## Yang diperiksa

- Validasi berkas dan struktur arsip proyek v1.3 sebagai sumber v1.4.
- Pemeriksaan keseimbangan delimiter pada semua sumber Dart dan file tes (bukan pengganti `dart analyze`).
- Kecocokan parameter RPC di `ShineService` dan nama/signature pada migrasi `004`.
- Keselarasan empat alur: `landing → menu`, `public browse → join`, `private code → join`, serta `gathering → draft → reveal → playing`.
- Efek kilatan putih **panggung penuh** diganti efek cahaya **terlokalisasi pada kartu**, warna latar arena dipertahankan, dan kondisi menunggu hanya diberi status kecil tanpa overlay penuh.
- Potret memakai `Image.asset(gaplessPlayback: true)` dan dipra-muat saat arena/reveal muncul.

## Belum diuji secara nyata

- `flutter analyze`, `flutter test`, `flutter run` dan build perangkat: SDK Flutter tidak tersedia di lingkungan penyusunan.
- Eksekusi migrasi, kebijakan RLS, RPC autentikasi anonim, serta Realtime dari server Supabase aktif: belum dijalankan.
- Pengukuran kedipan 30/60 fps di perangkat dan browser pengguna: belum dilakukan.

## Tes yang disediakan

- `test/arena_responsive_test.dart` (berasal dari versi sebelumnya): kestabilan panggung saat giliran berubah, ponsel 320/390 px, tablet, desktop, lanskap pendek, HP kritis.
- `test/home_flow_test.dart` (baru): layar pembuka dan menu ponsel kecil/desktop.

Urutan uji setempat: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d chrome`. Jalankan migrasi SQL `004` **setelah** `003` sebelum mencoba online.
