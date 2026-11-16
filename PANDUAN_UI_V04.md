# SHINE — Redesain UI/UX (v0.4)

Alur layar baru:

```
Beranda awal  ──►  Menu pilihan  ──►  Pemilih tim  ──►  In-game
(landing_page)     (menu_page)        (squad_picker)    (arena_page)
                        │
                        ├─► Arena Online (lembar kode ruang) ─► Lobi ─► In-game
                        └─► Koleksi tokoh (squad_picker, mode browse)
```

## Berkas
| Berkas | Isi |
|---|---|
| `lib/ui/landing_page.dart` | **BARU** Beranda awal: kipas 5 kartu + paralaks kursor/sentuh, logo berkilau, tombol Mulai (Enter/Spasi juga bisa). |
| `lib/ui/menu_page.dart` | **BARU** Menu pilihan mode (menggantikan `home_page.dart`). |
| `lib/ui/squad_picker.dart` | **BARU** (dipisah dari `home_page.dart`) Pemilih tim + mode `browse` untuk Koleksi Tokoh. |
| `lib/ui/how_to_play.dart` | **BARU** Lembar "Cara bermain" bersama. |
| `lib/ui/shine_ui.dart` | Tambahan: `shineIsWide`, `shineRoute`, `ShineEmbers`, `ShineWordmark`; `ShineScaffold(embers:)`. |
| `lib/ui/arena_page.dart` | In-game: bilah atas, dock kontrol (layar lebar), HUD/bangku menyesuaikan, hasil akhir. Logika permainan **tidak diubah**. |
| `lib/main.dart` | `home` kini `ShineLandingPage`. |
| `lib/ui/home_page.dart` | **DIHAPUS** (digantikan menu_page + squad_picker). |

## Breakpoint
`shineIsWide(size)`: lebar ≥ 900 px, atau lebar ≥ 640 px dan landscape (rasio > 1.25).
- **Lebar** (desktop, tablet landscape, ponsel landscape): dua kolom.
  Beranda = teks kiri + kartu kanan; Menu = mode kiri + "tokoh sorotan" & rekor kanan;
  Pemilih tim = kisi + panel detail/slot kanan; In-game = panggung kiri + dock kontrol 400 px kanan.
- **Sempit** (ponsel portrait): satu kolom, lebar konten maks. 560 px.

## Perilaku UX baru
- In-game: tombol menu (☰) dan riwayat kini terlihat di bilah atas; chip status giliran selalu tampak.
- In-game: tombol "atur ulang alokasi PA" di samping indikator PA.
- Label skill pada heksagon tidak lagi meluap; baris aksi menyusut otomatis di layar ≤ 360 px.
- Pemilih tim di desktop: arahkan kursor ke tokoh untuk melihat statistik & skill (tanpa tekan-tahan).
- Animasi dekoratif (percikan, kilau logo, denyut tombol) berhenti bila "kurangi animasi" aktif di sistem.

## Belum diuji
Lingkungan penyusun tidak punya Flutter SDK, jadi perubahan ini **belum** dijalankan lewat
`flutter analyze` / `flutter run`. Lihat catatan di pesan serah-terima untuk daftar cek.
