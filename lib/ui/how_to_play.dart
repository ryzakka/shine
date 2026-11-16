import 'package:flutter/material.dart';
import 'shine_ui.dart';

const _rules = <(IconData, String, String)>[
  (Icons.groups_2_outlined, 'Pilih tiga tokoh',
  'Satu tokoh aktif, dua lainnya cadangan.'),
  (Icons.bolt, 'Poin Aksi (PA)',
  'PA dasar naik 1 hingga 4 pada giliran awal. Kamu dapat menyimpan maksimal 4 PA.'),
  (Icons.tune, 'Alokasikan PA',
  'Bagi ke Serang, Bertahan, atau Cadangkan. Serangan dikurangi pertahanan lawan, lalu dihitung dengan pengali damage.'),
  (Icons.auto_awesome, 'Skill aktif',
  'Setiap tokoh punya satu skill. Pakai bila PA cukup dan cooldown siap.'),
  (Icons.swap_horiz, 'Pergantian',
  'Mengganti tokoh menghabiskan satu giliran penuh. Cooldown tetap turun saat tokoh di cadangan.'),
  (Icons.flag_outlined, 'Kemenangan',
  'Tim yang kehilangan ketiga tokohnya kalah.'),
  (Icons.public, 'Lobi online',
  'Tamu menekan Siap, host memilih timer 20–60 detik lalu menekan Mulai. Pemain dapat menyerah; host dapat membubarkan ruang. Tombol Beranda tidak mengakhiri pertandingan.'),
];

/// Lembar "Cara bermain" yang dipakai beranda awal maupun menu.
Future<void> showHowToPlay(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 680),
  builder: (context) => SafeArea(child: ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CARA BERMAIN', style: TextStyle(color: shineGold,
              fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
          const SizedBox(height: 14),
          Flexible(child: ListView.separated(
            shrinkWrap: true,
            itemCount: _rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final (icon, title, text) = _rules[i];
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: shineGold.withValues(alpha: .14),
                    border: Border.all(color: shineGold.withValues(alpha: .4)),
                  ),
                  child: Icon(icon, size: 19, color: shineGold),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. $title', style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(text, style: const TextStyle(
                        fontSize: 12.5, height: 1.45, color: shineMuted)),
                  ],
                )),
              ]);
            },
          )),
          const SizedBox(height: 18),
          ShineButton(
            label: 'MENGERTI', icon: Icons.check_rounded,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  )),
);
