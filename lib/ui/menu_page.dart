import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../game/saved_game.dart';
import '../online/shine_service.dart';
import 'arena_page.dart';
import 'how_to_play.dart';
import 'shine_ui.dart';
import 'squad_picker.dart';

typedef _RoomMap = Map<String, dynamic>;

enum _OnlineKind { create, join, resume }

class _OnlineChoice {
  const _OnlineChoice(this.kind, [this.code = '']);
  final _OnlineKind kind;
  final String code;
}

class ShineMenuPage extends StatefulWidget {
  const ShineMenuPage({super.key});
  @override
  State<ShineMenuPage> createState() => _ShineMenuPageState();
}

class _ShineMenuPageState extends State<ShineMenuPage> {
  static const _spotlight = <String>[
    'chaminhyuk', 'ragnarsigurdsson', 'baekseoyeon', 'kurokawaren',
    'linzixuan', 'hanseoah', 'zhangmingzhe', 'kwontaehyuk',
  ];

  late String _heroId = _spotlight[math.Random().nextInt(_spotlight.length)];
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

  void _cycleHero() {
    HapticFeedback.selectionClick();
    setState(() {
      final idx = (_spotlight.indexOf(_heroId) + 1) % _spotlight.length;
      _heroId = _spotlight[idx];
    });
  }

  // ───────────── Alur permainan ─────────────

  Future<List<String>?> selectSquad(List<String> defaults,
      {String title = 'RAKIT TIM'}) =>
      Navigator.push<List<String>>(context, shineRoute<List<String>>(
          SquadPicker(defaults: defaults, title: title)));

  Future<void> _openLocal(LocalBattle battle,
      {required bool againstBot, required int level}) async {
    await Navigator.of(context).push(shineRoute<void>(
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

  Future<void> _openOnline() async {
    final choice = await showModalBottomSheet<_OnlineChoice>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _OnlineSheet(),
    );
    if (choice == null || !mounted) return;
    switch (choice.kind) {
      case _OnlineKind.create:
        await online(joining: false, code: '');
      case _OnlineKind.join:
        await online(joining: true, code: choice.code);
      case _OnlineKind.resume:
        await resumeOnline();
    }
  }

  Future<void> online({required bool joining, required String code}) async {
    final lineup = await selectSquad(joining
        ? ['kwontaehyuk', 'kangjiwoo', 'choinari']
        : ['chaminhyuk', 'leejunseo', 'hanseoah']);
    if (lineup == null || !mounted) return;
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final info = joining
          ? await service.joinRoom(code, lineup)
          : await service.createRoom(lineup);
      if (!mounted) return;
      await Navigator.push(context, shineRoute<void>(
        OnlineArenaPage(roomId: info['id'] as String,
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
      final room = await showDialog<_RoomMap>(
          context: context,
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
      await Navigator.push(context, shineRoute<void>(
          OnlineArenaPage(roomId: room['id'] as String, roomCode: room['code'] as String)));
    } catch (error) { _notify('Tidak dapat membaca ruang: $error'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _openGallery() => Navigator.push(context, shineRoute<void>(
      const SquadPicker(title: 'KOLEKSI TOKOH', browse: true)));

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ───────────── Komponen Tanpa Kotak Berlebih ─────────────

  Widget _headerSection() => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ARENA TEMPUR', style: TextStyle(
                color: shineGold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 3.5)),
            SizedBox(height: 4),
            Text('Pilih Mode Duel', style: TextStyle(
                fontSize: 30, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -.5)),
          ]),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inlineStat('${records['wins']}', 'MENANG', shineJade),
            Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white12),
            _inlineStat('${records['losses']}', 'KALAH', shineEmber),
            Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white12),
            _inlineStat('${records['games']}', 'MAIN', shineGold),
          ],
        ),
      ],
    ),
  );

  Widget _inlineStat(String val, String label, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
          color: color, height: 1)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
          color: shineMuted, letterSpacing: 1.2)),
    ],
  );

  Widget _continueBanner() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : _continue,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [
              shineGold.withValues(alpha: .22),
              shineGold.withValues(alpha: .04),
            ]),
            border: Border(
              left: const BorderSide(color: shineGold, width: 4),
              top: BorderSide(color: shineGold.withValues(alpha: .3)),
              right: BorderSide(color: shineGold.withValues(alpha: .1)),
              bottom: BorderSide(color: shineGold.withValues(alpha: .1)),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.play_circle_fill_rounded, color: shineGold, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PERTANDINGAN TERSIMPAN', style: TextStyle(color: shineGold,
                  fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 2),
              Text('Lanjutkan Giliran ${saved!.battle.turn} • '
                  '${saved!.againstBot ? 'Vs Komputer' : 'Dua Pemain'}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: shineGold),
          ]),
        ),
      ),
    ),
  );

  Widget _difficultyStrip() {
    const items = [(0, 'SANTAI'), (1, 'NORMAL'), (2, 'AHLI')];
    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 14, color: shineMuted),
        const SizedBox(width: 8),
        const Text('TINGKAT AI:', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: shineMuted, letterSpacing: 1.5)),
        const Spacer(),
        for (final (val, label) in items)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => difficulty = val);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: difficulty == val
                        ? shineGold
                        : Colors.white.withValues(alpha: .06),
                  ),
                  child: Text(label, style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1,
                    color: difficulty == val ? const Color(0xFF1F1505) : Colors.white70,
                  )),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _modeList() => [
    if (saved != null) Reveal(child: _continueBanner()),
    Reveal(index: 1, child: _SleekModeBanner(
      big: true,
      accent: shineGold,
      tag: 'SOLO CAMPAIGN',
      title: 'LAWAN KOMPUTER',
      subtitle: 'Latih kombo & strategi melawan AI adaptif',
      art: 'chaminhyuk',
      onTap: busy ? null : startBot,
      bottomBar: _difficultyStrip(),
    )),
    const SizedBox(height: 12),
    Reveal(index: 2, child: _SleekModeBanner(
      accent: shineViolet,
      tag: 'REALTIME MULTIPLAYER',
      title: 'ARENA ONLINE',
      subtitle: 'Tantang pemain lain lewat kode ruang 1 vs 1',
      art: 'baekseoyeon',
      onTap: busy ? null : _openOnline,
    )),
    const SizedBox(height: 12),
    Reveal(index: 3, child: _SleekModeBanner(
      accent: shineAzure,
      tag: 'LOCAL HOTSEAT',
      title: 'DUA PEMAIN',
      subtitle: 'Bertarung bergantian di satu perangkat yang sama',
      art: 'kangjiwoo',
      onTap: busy ? null : local,
    )),
  ];

  Widget _narrowBody() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
    children: [
      Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _headerSection(),
          ..._modeList(),
        ]),
      )),
    ],
  );

  Widget _wideBody() => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1240),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 11, child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerSection(),
                ..._modeList(),
              ],
            ),
          ),
        )),
        const SizedBox(width: 44),
        Expanded(flex: 9, child: Reveal(
          index: 2,
          child: _OpenHeroShowcase(
            spec: characterById(_heroId),
            onNext: _cycleHero,
            onBrowseAll: _openGallery,
          ),
        )),
      ]),
    ),
  ));

  @override
  Widget build(BuildContext context) => ShineScaffold(
    embers: true,
    body: Stack(children: [
      SafeArea(child: LayoutBuilder(builder: (context, box) {
        final wide = shineIsWide(box.biggest);
        return Column(children: [
          _TopNav(
            onBack: () => Navigator.of(context).maybePop(),
            onGallery: busy ? null : _openGallery,
            onHelp: () => showHowToPlay(context),
          ),
          Expanded(child: wide ? _wideBody() : _narrowBody()),
        ]);
      })),
      if (busy) const Stack(children: [
        ModalBarrier(color: Colors.black54, dismissible: false),
        Center(child: CircularProgressIndicator()),
      ]),
    ]),
  );
}

class _TopNav extends StatelessWidget {
  const _TopNav({required this.onBack, required this.onGallery, required this.onHelp});
  final VoidCallback onBack, onHelp;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
    child: SizedBox(height: 50, child: Row(children: [
      IconButton(
          tooltip: 'Kembali ke beranda', onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: shineGold, size: 19)),
      const SizedBox(width: 4),
      const ShineWordmark(size: 21),
      const Spacer(),
      TextButton.icon(
        onPressed: onGallery,
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        icon: const Icon(Icons.style_outlined, size: 17, color: shineGold),
        label: const Text('KOLEKSI TOKOH', style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      ),
      const SizedBox(width: 4),
      IconButton(
          tooltip: 'Cara bermain', onPressed: onHelp,
          icon: const Icon(Icons.help_outline_rounded, color: shineGold, size: 21)),
    ])),
  );
}

class _SleekModeBanner extends StatefulWidget {
  const _SleekModeBanner({
    required this.tag, required this.title, required this.subtitle,
    required this.accent, required this.onTap, required this.art,
    this.big = false, this.bottomBar,
  });
  final String tag, title, subtitle, art;
  final Color accent;
  final VoidCallback? onTap;
  final bool big;
  final Widget? bottomBar;

  @override
  State<_SleekModeBanner> createState() => _SleekModeBannerState();
}

class _SleekModeBannerState extends State<_SleekModeBanner> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    final lit = _hover && enabled;
    final artWidth = w.big ? 190.0 : 145.0;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: lit ? 1.012 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.alphaBlend(
                    w.accent.withValues(alpha: lit ? .24 : .14),
                    const Color(0xFF1C182B)),
                const Color(0xB3100E1A),
              ],
            ),
            border: Border(
              left: BorderSide(color: w.accent, width: w.big ? 4.5 : 3.5),
              top: BorderSide(color: w.accent.withValues(alpha: lit ? .55 : .18)),
              right: BorderSide(color: Colors.white.withValues(alpha: lit ? .15 : .05)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: lit ? .15 : .05)),
            ),
            boxShadow: [
              if (lit || w.big)
                BoxShadow(
                  color: w.accent.withValues(alpha: lit ? .28 : .12),
                  blurRadius: lit ? 28 : 18,
                  spreadRadius: -6,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: w.onTap,
                    child: Stack(children: [
                      Positioned(
                        right: -6, top: 0, bottom: 0, width: artWidth,
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Colors.transparent, Colors.black],
                            stops: [0.05, 0.75],
                          ).createShader(rect),
                          child: Portrait(characterById(w.art),
                              radius: 0, border: false),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            22, w.big ? 22 : 16, artWidth - 36, w.big ? 22 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.tag, style: TextStyle(
                                color: w.accent, fontSize: 10,
                                fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                            const SizedBox(height: 5),
                            Row(children: [
                              Flexible(
                                child: Text(w.title, style: TextStyle(
                                    fontSize: w.big ? 22 : 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .8, height: 1.1)),
                              ),
                              const SizedBox(width: 8),
                              AnimatedSlide(
                                offset: Offset(lit ? 0.18 : 0, 0),
                                duration: const Duration(milliseconds: 180),
                                child: Icon(Icons.arrow_forward_rounded,
                                    size: w.big ? 20 : 17, color: w.accent),
                              ),
                            ]),
                            const SizedBox(height: 5),
                            Text(w.subtitle, style: TextStyle(
                                fontSize: 12.5, height: 1.35,
                                color: Colors.white.withValues(alpha: .72))),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
                if (w.bottomBar != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .28),
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .06))),
                    ),
                    child: w.bottomBar,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenHeroShowcase extends StatelessWidget {
  const _OpenHeroShowcase({
    required this.spec, required this.onNext, required this.onBrowseAll,
  });
  final CharacterSpec spec;
  final VoidCallback onNext, onBrowseAll;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onNext,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.7,
                  colors: [
                    shineGold.withValues(alpha: .22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            bottom: 60,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: ShaderMask(
                key: ValueKey(spec.id),
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                  stops: [0.0, 0.12, 0.72, 1.0],
                ).createShader(rect),
                child: Portrait(spec, radius: 24, border: false),
              ),
            ),
          ),
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Text('SOROTAN PETARUNG', style: TextStyle(
                      color: shineGold, fontSize: 10.5,
                      fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const Spacer(),
                  Text('Ketuk untuk ganti ↻', style: TextStyle(
                      color: Colors.white.withValues(alpha: .45), fontSize: 11)),
                ]),
                const SizedBox(height: 6),
                Text(spec.name.toUpperCase(), style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w900,
                    letterSpacing: 1, height: 1.05,
                    shadows: [Shadow(color: Colors.black, blurRadius: 16)])),
                const SizedBox(height: 8),
                Text('${spec.skill} — ${skillText(spec)}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.4,
                        color: Colors.white.withValues(alpha: .8))),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  StatPill('HP ${spec.hp}', icon: Icons.favorite, color: shineJade),
                  StatPill('ATK ${spec.attack}', icon: Icons.flash_on, color: shineEmber),
                  StatPill('${spec.cost} PA • CD ${spec.cooldown}',
                      icon: Icons.auto_awesome, color: shineViolet),
                ]),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OnlineSheet extends StatefulWidget {
  const _OnlineSheet();
  @override
  State<_OnlineSheet> createState() => _OnlineSheetState();
}

class _OnlineSheetState extends State<_OnlineSheet> {
  final code = TextEditingController();
  String? error;

  @override
  void dispose() { code.dispose(); super.dispose(); }

  void _join() {
    final value = code.text.trim();
    if (value.length != 6) {
      setState(() => error = 'Masukkan kode ruang enam karakter.');
      return;
    }
    Navigator.pop(context, _OnlineChoice(_OnlineKind.join, value));
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
        22, 0, 22, 18 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(children: [
          Icon(Icons.public, color: shineViolet),
          SizedBox(width: 10),
          Text('ARENA ONLINE', style: TextStyle(color: shineGold,
              fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
        ]),
        const SizedBox(height: 6),
        const Text('Duel 1 vs 1 lewat kode ruang. Setiap pemain membawa tiga tokoh.',
            style: TextStyle(color: shineMuted, fontSize: 13, height: 1.4)),
        const SizedBox(height: 18),
        ShineButton(
          icon: Icons.add_circle_outline,
          label: 'BUAT LOBI 1 vs 1', subtitle: 'Bagikan kode ke temanmu',
          onPressed: () =>
              Navigator.pop(context, const _OnlineChoice(_OnlineKind.create)),
        ),
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
            textInputAction: TextInputAction.done,
            onChanged: (_) { if (error != null) setState(() => error = null); },
            onSubmitted: (_) => _join(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Fa-f0-9]'))],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                letterSpacing: 6, color: shineGold),
            decoration: InputDecoration(
              counterText: '', hintText: 'A1B2C3', filled: true,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: .2), letterSpacing: 6),
              fillColor: Colors.black.withValues(alpha: .28),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: error == null ? Colors.white12 : shineEmber)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: shineGold, width: 1.4)),
            ),
          )),
          const SizedBox(width: 10),
          SizedBox(width: 118, child: ShineButton(
              label: 'GABUNG', height: 56, onPressed: _join)),
        ]),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error!, style: const TextStyle(color: shineEmber, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () =>
              Navigator.pop(context, const _OnlineChoice(_OnlineKind.resume)),
          icon: const Icon(Icons.restore, size: 18),
          label: const Text('Lobi saya / lanjutkan pertandingan'),
        ),
      ],
    ),
  ));
}