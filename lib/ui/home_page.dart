import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../game/saved_game.dart';
import 'arena_page.dart';
import 'online_rooms_page.dart';
import 'squad_picker.dart';
import 'shine_ui.dart';

class ShineHomePage extends StatefulWidget {
  const ShineHomePage({super.key});
  @override
  State<ShineHomePage> createState() => _ShineHomePageState();
}

class _ShineHomePageState extends State<ShineHomePage> {
  bool busy = false;
  bool _entered = false;
  int difficulty = 1;
  SavedGame? saved;
  Map<String, int> records = const {'wins': 0, 'losses': 0, 'games': 0};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final game = await LocalGameStorage.load();
    final stats = await LocalGameStorage.records();
    if (mounted) setState(() { saved = game; records = stats; });
  }

  Future<List<String>?> selectSquad(List<String> defaults, {String title = 'RAKIT TIM'}) =>
      Navigator.push<List<String>>(context, MaterialPageRoute(
          builder: (_) => SquadPicker(defaults: defaults, title: title)));

  Future<void> _openLocal(LocalBattle battle,
      {required bool againstBot, required int level}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        LocalArenaPage(battle: battle, againstBot: againstBot, difficulty: level)));
    await _load();
  }

  Future<void> startBot() async {
    final a = await selectSquad(['chaminhyuk', 'leejunseo', 'hanseoah']);
    if (a == null || !mounted) return;
    final ids = characters.map((e) => e.id).where((id) => !a.contains(id)).toList()
      ..shuffle(math.Random());
    final b = ids.take(3).toList();
    await LocalGameStorage.remove();
    if (!mounted) return;
    await _openLocal(LocalBattle(teamA: a, teamB: b),
        againstBot: true, level: difficulty);
  }

  Future<void> local() async {
    final a = await selectSquad(['chaminhyuk', 'leejunseo', 'hanseoah'], title: 'TIM A');
    if (a == null || !mounted) return;
    final b = await selectSquad(['kwontaehyuk', 'kangjiwoo', 'choinari'], title: 'TIM B');
    if (b == null || !mounted) return;
    await LocalGameStorage.remove();
    if (!mounted) return;
    await _openLocal(LocalBattle(teamA: a, teamB: b),
        againstBot: false, level: 1);
  }

  Future<void> _continue() async {
    if (saved == null) return;
    await _openLocal(saved!.battle,
        againstBot: saved!.againstBot, level: saved!.difficulty);
  }

  static const _rules = <(IconData, String, String)>[
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
    'Host membuat ruang dan pemain kedua bergabung. Setelah dua pemain hadir, masing-masing memilih 3 kartu. Keenam kartu diungkap bergiliran sebelum pertarungan dimulai otomatis.'),
  ];

  void _howToPlay() => showModalBottomSheet<void>(context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      child: Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CARA BERMAIN', style: TextStyle(color: shineGold,
                  fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const SizedBox(height: 14),
              Flexible(child: ListView.separated(
                shrinkWrap: true, itemCount: _rules.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final (icon, title, text) = _rules[i];
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 38, height: 38,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                            color: shineGold.withValues(alpha: .14),
                            border: Border.all(color: shineGold.withValues(alpha: .4))),
                        child: Icon(icon, size: 19, color: shineGold)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${i + 1}. $title', style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(text, style: const TextStyle(
                          fontSize: 12.5, height: 1.45, color: shineMuted)),
                    ])),
                  ]);
                },
              )),
              const SizedBox(height: 18),
              ShineButton(label: 'MULAI BERMAIN', icon: Icons.play_arrow,
                  onPressed: () => Navigator.pop(context)),
            ]),
      ),
    )),
  );

  // ───────────── Bagian layar ─────────────

  Widget _continueCard() => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: ShinePanel(
      glow: shineGold, borderColor: shineGold.withValues(alpha: .55),
      onTap: busy ? null : _continue,
      child: Row(children: [
        Container(width: 46, height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(colors: [shineGoldLight, shineGoldDeep])),
            child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF241A08), size: 30)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LANJUTKAN PERTANDINGAN', style: TextStyle(color: shineGold,
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
          const SizedBox(height: 3),
          Text('Giliran ${saved!.battle.turn} • ${saved!.againstBot ? 'Vs Komputer' : 'Dua pemain'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ])),
        const Icon(Icons.chevron_right, color: shineGold),
      ]),
    ),
  );

  Widget _difficultySelector() {
    Widget seg(int value, String label, IconData icon) {
      final on = difficulty == value;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => difficulty = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: on ? shineGold.withValues(alpha: .18) : Colors.transparent,
            border: Border.all(color: on ? shineGold : Colors.transparent, width: 1.3),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: on ? shineGold : shineMuted),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800, color: on ? shineGold : shineMuted)),
          ]),
        ),
      ));
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .28),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10)),
      child: Row(children: [
        seg(0, 'Santai', Icons.sentiment_satisfied_alt),
        seg(1, 'Normal', Icons.speed),
        seg(2, 'Ahli', Icons.local_fire_department),
      ]),
    );
  }

  Widget _statTile(String value, String label, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
          fontSize: 10.5, color: shineMuted, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _records() => ShinePanel(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: IntrinsicHeight(child: Row(children: [
      _statTile('${records['wins']}', 'MENANG', shineJade),
      VerticalDivider(color: Colors.white.withValues(alpha: .1), width: 1),
      _statTile('${records['losses']}', 'KALAH', shineEmber),
      VerticalDivider(color: Colors.white.withValues(alpha: .1), width: 1),
      _statTile('${records['games']}', 'MAIN', shineGold),
    ])),
  );

  Widget _playModes() => Reveal(index: 2,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('MAIN SEKARANG'),
      ShineButton(icon: Icons.smart_toy_outlined, height: 62,
          label: 'LAWAN KOMPUTER', subtitle: 'Tanpa internet • lawan acak',
          onPressed: busy ? null : startBot),
      _difficultySelector(),
      const SizedBox(height: 12),
      ShineButton(primary: false, icon: Icons.people_outline,
          label: 'DUA PEMAIN', subtitle: 'Satu perangkat, bergantian',
          onPressed: busy ? null : local),
    ]));

  Widget _recordSection() => Reveal(index: 3,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('CATATAN VS KOMPUTER'),
      _records(),
    ]));

  Future<void> _openOnlineDirectory() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const OnlineRoomsPage()));
  }

  Widget _startScreen() => SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500),
      child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(flex: 3),
          const FittedBox(fit: BoxFit.scaleDown, child: Text('SHINE',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 96, fontWeight: FontWeight.w900,
              color: shineGoldLight, letterSpacing: 14,
              shadows: [Shadow(color: Color(0x66EFC483), blurRadius: 38)]))),
          const Spacer(flex: 2),
          ShineButton(icon: Icons.play_arrow_rounded, height: 66,
            label: 'MULAI', onPressed: () => setState(() => _entered = true)),
          const SizedBox(height: 28),
          const Center(child: Text('v1.4.0',
            style: TextStyle(fontSize: 12, color: shineMuted, letterSpacing: 2.4))),
          const Spacer(flex: 1),
        ]),
    ),
  )));

  Widget _menuScreen() => SafeArea(child: LayoutBuilder(builder: (context, bounds) {
    final wide = bounds.maxWidth >= 820;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 32), children: [
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1060),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(onPressed: () => setState(() => _entered = false),
              icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: 'Kembali ke layar awal'),
            const SizedBox(width: 6),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
                Text('SHINE', style: TextStyle(color: shineGoldLight,
                  fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 5)),
                Text('v1.4.0', style: TextStyle(color: shineMuted,
                  fontSize: 10, letterSpacing: 1.5)),
              ])),
            TextButton.icon(onPressed: _howToPlay, icon: const Icon(Icons.help_outline),
              label: const Text('PANDUAN')),
          ]),
          const SizedBox(height: 12),
          const Text('PILIH MODE BERMAIN', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w900, color: shineMuted, letterSpacing: 2)),
          const SizedBox(height: 18),
          if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _playModes(),
              if (saved != null) _continueCard(),
            ])),
            const SizedBox(width: 20),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _onlineMenuCard(), const SizedBox(height: 12),
              _recordSection(),
            ])),
          ]) else ...[
            _onlineMenuCard(), const SizedBox(height: 14),
            _playModes(),
            if (saved != null) _continueCard(),
            _recordSection(),
          ],
          const SizedBox(height: 30),
          const Center(child: Text('SHINE  •  v1.4.0',
            style: TextStyle(color: shineMuted, fontSize: 11, letterSpacing: 2))),
        ]))),
    ]);
  }));

  Widget _onlineMenuCard() => ShinePanel(tint: shineAzure,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [
        Icon(Icons.language, color: shineAzure), SizedBox(width: 10),
        Expanded(child: Text('MULTIPLAYER ONLINE', style: TextStyle(
          color: shineAzure, fontWeight: FontWeight.w900, letterSpacing: 1.4))),
      ]),
      const SizedBox(height: 10),
      const Text('Buat ruang publik atau privat, lihat daftar arena terbuka, '
        'dan bertarung dengan nama pemainmu sendiri.',
        style: TextStyle(fontSize: 12, color: shineMuted, height: 1.5)),
      const SizedBox(height: 18),
      ShineButton(icon: Icons.public, height: 60, label: 'MASUK ARENA ONLINE',
        onPressed: busy ? null : _openOnlineDirectory),
    ]));

  @override
  Widget build(BuildContext context) => ShineScaffold(
    body: Stack(children: [
      Positioned.fill(child: _entered ? _menuScreen() : _startScreen()),
      if (busy) const Positioned.fill(child: ColoredBox(
        color: Color(0x99000000), child: Center(child: CircularProgressIndicator()))),
    ]),
  );

}

