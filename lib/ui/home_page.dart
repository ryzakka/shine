import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../game/saved_game.dart';
import '../online/shine_service.dart';
import 'arena_page.dart';
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
    final lineup = await selectSquad(joining
        ? ['kwontaehyuk', 'kangjiwoo', 'choinari']
        : ['chaminhyuk', 'leejunseo', 'hanseoah']);
    if (lineup == null || !mounted) return;
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final info = joining
          ? await service.joinRoom(code.text, lineup)
          : await service.createRoom(lineup);
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
    'Tamu menekan Siap, host memilih timer 20–60 detik lalu menekan Mulai. Pemain dapat menyerah; host dapat membubarkan ruang. Tombol Beranda tidak mengakhiri pertandingan.'),
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
      ShineButton(primary: false, icon: Icons.add_circle_outline,
          label: 'BUAT LOBI 1 vs 1', subtitle: 'Bagikan kode ke temanmu',
          onPressed: busy ? null : () => online(joining: false)),
      Padding(padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('ATAU GABUNG', style: TextStyle(fontSize: 10,
                    color: shineMuted, letterSpacing: 2, fontWeight: FontWeight.w800))),
            Expanded(child: Divider(color: Colors.white.withValues(alpha: .12))),
          ])),
      Row(children: [
        Expanded(child: TextField(
          controller: code, maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Fa-f0-9]'))],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
              letterSpacing: 6, color: shineGold),
          decoration: InputDecoration(
            counterText: '', hintText: 'A1B2C3', filled: true,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: .2), letterSpacing: 6),
            fillColor: Colors.black.withValues(alpha: .28),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: shineGold, width: 1.4)),
          ),
        )),
        const SizedBox(width: 10),
        SizedBox(width: 118, child: ShineButton(label: 'GABUNG', height: 56,
            onPressed: busy ? null : () => online(joining: true))),
      ]),
      const SizedBox(height: 6),
      TextButton.icon(onPressed: busy ? null : resumeOnline,
          icon: const Icon(Icons.restore, size: 18),
          label: const Text('Lobi saya / lanjutkan pertandingan')),
    ]),
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
          child: const Text('SHINE', style: TextStyle(fontSize: 58,
              fontWeight: FontWeight.w900, letterSpacing: 12, color: Colors.white,
              height: 1, shadows: [Shadow(color: Color(0x99EFC483), blurRadius: 28)])),
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

// ───────────── Pemilih tim ─────────────

class SquadPicker extends StatefulWidget {
  const SquadPicker({super.key, required this.defaults, this.title = 'RAKIT TIM'});
  final List<String> defaults;
  final String title;
  @override
  State<SquadPicker> createState() => _SquadPickerState();
}

class _SquadPickerState extends State<SquadPicker> {
  late final List<String> selected = [...widget.defaults];

  void _toggle(CharacterSpec c) {
    final isSelected = selected.contains(c.id);
    if (!isSelected && selected.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Satu tim hanya boleh membawa tiga tokoh.')));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => isSelected ? selected.remove(c.id) : selected.add(c.id));
  }

  void _detail(CharacterSpec c) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Portrait(c, width: 104, height: 150, radius: 14),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatPill('HP ${c.hp}', icon: Icons.favorite, color: shineJade),
              StatPill('ATK ${c.attack}', icon: Icons.bolt, color: shineEmber),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: shineViolet.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: shineViolet.withValues(alpha: .4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, size: 16, color: shineViolet),
                  const SizedBox(width: 6),
                  Expanded(child: Text(c.skill, style: const TextStyle(
                      fontWeight: FontWeight.w800, color: shineViolet))),
                ]),
                const SizedBox(height: 4),
                Text(skillText(c), style: const TextStyle(fontSize: 12, height: 1.4)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  StatPill('${c.cost} PA', color: shineGold),
                  StatPill('CD ${c.cooldown}', color: shineGold),
                  StatPill(skillKindLabel(c.kind), color: shineViolet),
                ]),
              ]),
            ),
          ])),
        ]),
        const SizedBox(height: 18),
        ShineButton(
            label: selected.contains(c.id) ? 'LEPAS DARI TIM' : 'MASUKKAN KE TIM',
            icon: selected.contains(c.id) ? Icons.remove_circle_outline : Icons.add_circle_outline,
            primary: !selected.contains(c.id),
            onPressed: () { Navigator.pop(ctx); _toggle(c); }),
      ]),
    )),
  );

  Widget _slot(int i) {
    if (i >= selected.length) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add, color: Colors.white38),
          const SizedBox(height: 2),
          Text('SLOT ${i + 1}', style: const TextStyle(
              fontSize: 10, color: Colors.white38, letterSpacing: 1.5)),
        ]),
      );
    }
    final c = characterById(selected[i]);
    return GestureDetector(
      onTap: () => setState(() => selected.removeAt(i)),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: shineGold.withValues(alpha: .3), blurRadius: 16, spreadRadius: -4)]),
        child: Stack(fit: StackFit.expand, children: [
          Portrait(c, radius: 14),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [.5, 1], colors: [Colors.transparent, Colors.black.withValues(alpha: .85)])))),
          Positioned(left: 6, right: 6, bottom: 5, child: Text(c.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
          Positioned(top: 5, left: 5, child: CircleAvatar(radius: 10,
              backgroundColor: shineGold, child: Text('${i + 1}', style: const TextStyle(
                  color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)))),
          const Positioned(top: 5, right: 5, child: Icon(Icons.cancel, size: 18, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _tile(CharacterSpec c) {
    final isSelected = selected.contains(c.id);
    final full = selected.length >= 3;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: !isSelected && full ? .5 : 1,
      child: GestureDetector(
        onTap: () => _toggle(c),
        onLongPress: () => _detail(c),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? shineGold : Colors.white12,
                  width: isSelected ? 2.2 : 1),
              boxShadow: isSelected
                  ? [BoxShadow(color: shineGold.withValues(alpha: .4), blurRadius: 18, spreadRadius: -2)]
                  : null),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              Portrait(c, radius: 0, border: false),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [.5, 1],
                  colors: [Colors.transparent, Colors.black.withValues(alpha: .92)]))),
              Positioned(left: 8, right: 8, bottom: 8, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('ATK ${c.attack}  •  HP ${c.hp}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70)),
                Text(c.skill, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: shineGold, fontWeight: FontWeight.w700)),
              ])),
              if (isSelected) Positioned(top: 7, right: 7, child: CircleAvatar(
                  radius: 13, backgroundColor: shineGold,
                  child: Text('${selected.indexOf(c.id) + 1}', style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _teamSummary() => ShinePanel(
    padding: const EdgeInsets.all(10), radius: 18,
    child: Column(children: [
      SizedBox(height: 118, child: Row(children: [
        for (var i = 0; i < 3; i++) Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4), child: _slot(i))),
      ])),
      const SizedBox(height: 10),
      Text('${selected.length}/3 tokoh • ketuk untuk melepas',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: shineMuted)),
    ]));

  Widget _characterGrid() => GridView.builder(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190, childAspectRatio: .66,
        crossAxisSpacing: 12, mainAxisSpacing: 12),
    itemCount: characters.length,
    itemBuilder: (context, i) => _tile(characters[i]));

  @override
  Widget build(BuildContext context) {
    final remaining = 3 - selected.length;
    return ShineScaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        TextButton(onPressed: selected.isEmpty ? null : () => setState(selected.clear),
            child: const Text('Kosongkan')),
      ]),
      body: SafeArea(child: LayoutBuilder(builder: (context, size) {
        final wide = size.maxWidth >= 800;
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(children: [
            Expanded(child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 300, child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SectionLabel('TIM PILIHAN'),
                      _teamSummary(),
                      const SizedBox(height: 14),
                      const Text('Pilih tepat tiga tokoh. Ketuk kartu untuk memilih. '
                          'Tahan kartu untuk melihat skill, biaya PA, dan cooldown.',
                          style: TextStyle(color: shineMuted, fontSize: 12, height: 1.5)),
                    ]))),
                  VerticalDivider(width: 1, color: Colors.white.withValues(alpha: .12)),
                  Expanded(child: _characterGrid()),
                ])
              : Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                      child: _teamSummary()),
                  Expanded(child: _characterGrid()),
                ])),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF14111F),
                  border: Border(top: BorderSide(color: shineGold.withValues(alpha: .2)))),
              child: Center(child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: ShineButton(
                  icon: remaining == 0 ? Icons.check : Icons.person_add_alt,
                  label: remaining == 0 ? 'MULAI DENGAN 3 TOKOH' : 'PILIH $remaining TOKOH LAGI',
                  onPressed: remaining == 0
                      ? () => Navigator.pop(context, List<String>.from(selected)) : null))),
            ),
          ]),
        ));
      })),
    );
  }

}