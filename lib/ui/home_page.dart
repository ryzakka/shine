import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../game/saved_game.dart';
import '../online/shine_service.dart';
import 'arena_page.dart';
import 'squad_picker.dart';
import 'shine_ui.dart';

class ShineHomePage extends StatefulWidget {
  const ShineHomePage({super.key});
  @override
  State<ShineHomePage> createState() => _ShineHomePageState();
}

class _ShineHomePageState extends State<ShineHomePage> {
  final code = TextEditingController();
  bool busy = false;
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

  @override
  void dispose() { code.dispose(); super.dispose(); }

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

  Future<void> online({required bool joining}) async {
    if (joining && code.text.trim().length != 6) {
      _notify('Masukkan kode ruang enam karakter.');
      return;
    }
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final info = joining
          ? await service.joinRoom(code.text, const [])
          : await service.createRoom(const []);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => OnlineArenaPage(roomId: info['id'] as String,
            roomCode: info['code'] as String),
      ));
    } catch (error) {
      _notify('Tidak dapat mengakses ruang: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resumeOnline() async {
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final rooms = await service.myRooms();
      if (!mounted) return;
      if (rooms.isEmpty) { _notify('Belum ada ruang aktif yang bisa dilanjutkan.'); return; }
      final room = await showDialog<Map<String, dynamic>>(context: context,
          builder: (context) => SimpleDialog(
              title: const Text('Ruang daring kamu'),
              children: [
                for (final r in rooms) SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.sports_esports, color: shineGold),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${r['code']}', style: const TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 16))),
                        r['status'] == 'playing'
                            ? const StatPill('Sedang bermain', icon: Icons.bolt, color: shineEmber)
                            : const StatPill('Lobi menunggu', icon: Icons.hourglass_bottom),
                      ])),
                ),
              ]));
      if (room == null || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
          OnlineArenaPage(roomId: room['id'] as String, roomCode: room['code'] as String)));
    } catch (error) { _notify('Tidak dapat membaca ruang: $error'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Widget _onlineCard() => ShinePanel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('DUA PEMAIN, SATU PANGGUNG', style: TextStyle(
        color: shineGold, fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text('Bergabung dahulu. Kalian baru memilih 3 kartu setelah hadir berdua.',
        style: TextStyle(fontSize: 12, color: shineMuted, height: 1.45)),
      const SizedBox(height: 14),
      Wrap(spacing: 6, runSpacing: 7, children: const [
        StatPill('1 • MASUK LOBI', icon: Icons.groups_outlined, color: shineAzure),
        StatPill('2 • PILIH KARTU', icon: Icons.style_outlined, color: shineGold),
        StatPill('3 • REVEAL & DUEL', icon: Icons.auto_awesome, color: shineViolet),
      ]),
      const SizedBox(height: 18),
      ShineButton(primary: false, icon: Icons.add_circle_outline,
        label: 'BUAT RUANG BARU', subtitle: 'Undang teman dengan kode 6 karakter',
        onPressed: busy ? null : () => online(joining: false)),
      Padding(padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('ATAU GABUNG', style: TextStyle(fontSize: 10,
              color: shineMuted, letterSpacing: 2, fontWeight: FontWeight.w800))),
          Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
        ])),
      LayoutBuilder(builder: (context, bounds) {
        final codeInput = TextField(
          controller: code, maxLength: 6, textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Fa-f0-9]'))],
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
            letterSpacing: 4, color: shineGold),
          decoration: InputDecoration(counterText: '', hintText: 'A1B2C3',
            filled: true, fillColor: Colors.black.withValues(alpha: .28),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: shineGold, width: 1.4))));
        final join = ShineButton(label: 'GABUNG', height: 56,
          onPressed: busy ? null : () => online(joining: true));
        if (bounds.maxWidth < 365) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            codeInput, const SizedBox(height: 10), join]);
        }
        return Row(children: [Expanded(child: codeInput), const SizedBox(width: 10),
          SizedBox(width: 118, child: join)]);
      }),
      const SizedBox(height: 10),
      TextButton.icon(onPressed: busy ? null : resumeOnline,
        icon: const Icon(Icons.restore, size: 18),
        label: const Text('KEMBALI KE RUANG SAYA')),
    ]));

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

  Widget _onlineSection() => Reveal(index: 4,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('ARENA ONLINE'),
      _onlineCard(),
    ]));

  @override
  Widget build(BuildContext context) => ShineScaffold(
    body: Stack(children: [
      SafeArea(child: LayoutBuilder(builder: (context, size) {
        final wide = size.maxWidth >= 880;
        return ListView(padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 0,
            wide ? 28 : 18, 28), children: [
          Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 1160 : 620),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('CARA BERMAIN'),
                    onPressed: _howToPlay)),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 6, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Reveal(child: _Hero()),
                    if (saved != null) Reveal(index: 1, child: _continueCard()),
                    _playModes(),
                  ])),
                  const SizedBox(width: 26),
                  Expanded(flex: 5, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 20),
                    _onlineSection(),
                    _recordSection(),
                    const SizedBox(height: 18),
                    const Text('Setiap giliran, tentukan PA serang, pertahanan, '
                        'cadangan, dan kemampuan khas. Bermain lokal bisa tanpa internet.',
                        style: TextStyle(fontSize: 12, color: shineMuted, height: 1.5)),
                  ])),
                ])
              else ...[
                const Reveal(child: _Hero()),
                if (saved != null) Reveal(index: 1, child: _continueCard()),
                _playModes(),
                _recordSection(),
                _onlineSection(),
              ],
              const SizedBox(height: 24),
              const Text('Shine • Manhwa Card Battle  |  3 tokoh per tim',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: shineMuted)),
            ]),
          )),
        ]);
      })),
      if (busy) const Stack(children: [
        ModalBarrier(color: Colors.black54, dismissible: false),
        Center(child: CircularProgressIndicator()),
      ]),
    ]),
  );

}

/// Tiga kartu bergaya kipas dengan judul emas di bawahnya.
class _Hero extends StatelessWidget {
  const _Hero();

  Widget _card(String id, double w, double h, double angle, Offset offset) {
    final spec = characterById(id);
    return Transform.translate(offset: offset, child: Transform.rotate(angle: angle,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .6),
                  blurRadius: 22, offset: const Offset(0, 12))]),
          child: Portrait(spec, width: w, height: h, radius: 16),
        )));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 350,
    child: Stack(children: [
      Positioned(top: 6, left: 0, right: 0, height: 240, child: Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: 340, height: 240,
              child: Stack(alignment: Alignment.center, children: [
                _card('baekseoyeon', 112, 176, -.14, const Offset(-98, 14)),
                _card('ragnarsigurdsson', 112, 176, .14, const Offset(98, 14)),
                _card('chaminhyuk', 134, 212, 0, Offset.zero),
              ]))))),
      Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              stops: const [.45, .72],
              colors: [Colors.transparent, shineInk.withValues(alpha: .92)]))))),
      Align(alignment: Alignment.bottomCenter, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [shineGoldLight, shineGold, shineGoldDeep]).createShader(r),
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('SHINE', style: TextStyle(fontSize: 58,
              fontWeight: FontWeight.w900, letterSpacing: 12, color: Colors.white,
              height: 1, shadows: [Shadow(color: Color(0x99EFC483), blurRadius: 28)]))),
        ),
        const SizedBox(height: 8),
        const Text('MANHWA CARD BATTLE', style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 4, color: shineMuted)),
        const SizedBox(height: 12),
        const Wrap(spacing: 8, children: [
          StatPill('26 TOKOH', icon: Icons.person_outline, color: shineGold),
          StatPill('3 KARTU', icon: Icons.style_outlined, color: shineGold),
          StatPill('1 vs 1', icon: Icons.bolt, color: shineGold),
        ]),
      ])),
    ]),
  );
}

