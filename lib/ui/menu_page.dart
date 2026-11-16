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

enum _OnlineKind { create, join, resume }

class _OnlineChoice {
  const _OnlineChoice(this.kind, [this.code = '']);
  final _OnlineKind kind;
  final String code;
}

/// Menu utama: memilih mode permainan. Dibuka dari beranda awal.
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

  late final String _heroId = _spotlight[math.Random().nextInt(_spotlight.length)];
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

  // ───────────── Bagian layar ─────────────

  Widget _heading() => const Padding(
    padding: EdgeInsets.only(top: 6, bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pilih mode permainan', style: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w900, height: 1.15)),
      SizedBox(height: 4),
      Text('Susun tiga tokoh, lalu masuk ke arena.',
          style: TextStyle(fontSize: 14, color: shineMuted)),
    ]),
  );

  Widget _continueCard() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ShinePanel(
      glow: shineGold, borderColor: shineGold.withValues(alpha: .55),
      onTap: busy ? null : _continue,
      child: Row(children: [
        Container(width: 46, height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(colors: [shineGoldLight, shineGoldDeep])),
            child: const Icon(Icons.play_arrow_rounded,
                color: Color(0xFF241A08), size: 30)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('LANJUTKAN PERTANDINGAN', style: TextStyle(color: shineGold,
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
          const SizedBox(height: 3),
          Text('Giliran ${saved!.battle.turn} • '
              '${saved!.againstBot ? 'Vs Komputer' : 'Dua pemain'}',
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
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => difficulty = value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
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
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10)),
      child: Row(children: [
        seg(0, 'Santai', Icons.sentiment_satisfied_alt),
        seg(1, 'Normal', Icons.speed),
        seg(2, 'Ahli', Icons.local_fire_department),
      ]),
    );
  }

  Widget _botCard() => Reveal(index: 1, child: _ModeCard(
    big: true, accent: shineGold, icon: Icons.smart_toy_outlined,
    title: 'LAWAN KOMPUTER', subtitle: 'Tanpa internet • lawan acak',
    art: 'chaminhyuk', onTap: busy ? null : startBot,
    footer: _difficultySelector(),
  ));

  Widget _duoCard() => Reveal(index: 2, child: _ModeCard(
    accent: shineAzure, icon: Icons.people_outline,
    title: 'DUA PEMAIN', subtitle: 'Satu perangkat, bergantian',
    art: 'kangjiwoo', onTap: busy ? null : local,
  ));

  Widget _onlineCard() => Reveal(index: 3, child: _ModeCard(
    accent: shineViolet, icon: Icons.public,
    title: 'ARENA ONLINE', subtitle: 'Duel 1 vs 1 lewat kode ruang',
    badge: 'ONLINE', art: 'baekseoyeon',
    onTap: busy ? null : _openOnline,
  ));

  Widget _utilities() => Reveal(index: 4, child: Row(children: [
    Expanded(child: _UtilityTile(icon: Icons.collections_bookmark_outlined,
        label: 'Koleksi tokoh', onTap: busy ? null : _openGallery)),
    const SizedBox(width: 12),
    Expanded(child: _UtilityTile(icon: Icons.menu_book_outlined,
        label: 'Cara bermain', onTap: () => showHowToPlay(context))),
  ]));

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

  List<Widget> _modes() => [
    if (saved != null) Reveal(child: _continueCard()),
    _botCard(),
    const SizedBox(height: 14),
    _duoCard(),
    const SizedBox(height: 14),
    _onlineCard(),
    const SizedBox(height: 14),
    _utilities(),
  ];

  Widget _narrowBody() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
    children: [
      Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _heading(),
          ..._modes(),
          Reveal(index: 5, child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('CATATAN VS KOMPUTER'),
            _records(),
          ])),
        ]),
      )),
    ],
  );

  Widget _wideBody() => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1200),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 11, child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _heading(),
            ..._modes(),
          ]),
        )),
        const SizedBox(width: 32),
        Expanded(flex: 9, child: Reveal(index: 2, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Showcase(spec: characterById(_heroId))),
            const SizedBox(height: 14),
            _records(),
          ],
        ))),
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
          _TopBar(
            onBack: () => Navigator.of(context).maybePop(),
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

// ───────────── Komponen ─────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onHelp});
  final VoidCallback onBack, onHelp;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
    child: SizedBox(height: 52, child: Row(children: [
      IconButton(
          tooltip: 'Kembali ke beranda', onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: shineGold, size: 20)),
      const SizedBox(width: 4),
      const ShineWordmark(size: 22),
      const Spacer(),
      IconButton(
          tooltip: 'Cara bermain', onPressed: onHelp,
          icon: const Icon(Icons.help_outline, color: shineGold)),
    ])),
  );
}

/// Kartu mode permainan. [big] untuk mode utama; [art] menampilkan potret
/// tokoh yang memudar di sisi kanan.
class _ModeCard extends StatefulWidget {
  const _ModeCard({required this.title, required this.subtitle,
    required this.icon, required this.accent, required this.onTap,
    this.art, this.big = false, this.footer, this.badge});
  final String title, subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final String? art, badge;
  final bool big;
  final Widget? footer;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    final lit = _hover && enabled;
    final r = BorderRadius.circular(w.big ? 24 : 20);
    final artWidth = w.big ? 160.0 : 104.0;
    final onAccent = w.accent == shineGold ? const Color(0xFF241A08) : Colors.white;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : .5,
        child: AnimatedScale(
          scale: lit ? 1.012 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                      w.accent.withValues(alpha: lit ? .26 : .16),
                      const Color(0xFF262136)),
                  const Color(0xFF161324),
                ],
              ),
              border: Border.all(
                color: w.accent.withValues(
                    alpha: lit ? .95 : (w.big ? .62 : .34)),
                width: w.big ? 1.6 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: w.accent.withValues(
                      alpha: lit ? .4 : (w.big ? .26 : .1)),
                  blurRadius: lit ? 34 : 24, spreadRadius: -6,
                ),
                BoxShadow(color: Colors.black.withValues(alpha: .4),
                    blurRadius: 16, offset: const Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: w.onTap,
                      child: Stack(children: [
                        if (w.art != null) Positioned(
                          right: 0, top: 0, bottom: 0, width: artWidth,
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (rect) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.transparent, Colors.black],
                              stops: [0, .65],
                            ).createShader(rect),
                            child: Portrait(characterById(w.art!),
                                radius: 0, border: false),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              18, w.big ? 24 : 18, artWidth - 28, w.big ? 24 : 18),
                          child: Row(children: [
                            Container(
                              width: w.big ? 52 : 44, height: w.big ? 52 : 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color.lerp(w.accent, Colors.white, .25)!,
                                    Color.lerp(w.accent, Colors.black, .3)!,
                                  ],
                                ),
                                boxShadow: [BoxShadow(
                                    color: w.accent.withValues(alpha: .5),
                                    blurRadius: 16, spreadRadius: -2)],
                              ),
                              child: Icon(w.icon, color: onAccent,
                                  size: w.big ? 28 : 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (w.badge != null) Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: StatPill(w.badge!, color: w.accent),
                                ),
                                Text(w.title, maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: w.big ? 18 : 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2, height: 1.15)),
                                const SizedBox(height: 4),
                                Text(w.subtitle, maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, height: 1.3,
                                        color: Colors.white70)),
                              ],
                            )),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  if (w.footer != null) Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: w.footer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UtilityTile extends StatelessWidget {
  const _UtilityTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ShinePanel(
    radius: 16,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    onTap: onTap,
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 20, color: shineGold),
      const SizedBox(width: 10),
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
    ]),
  );
}

/// Panel "tokoh sorotan" di sisi kanan menu pada layar lebar.
class _Showcase extends StatelessWidget {
  const _Showcase({required this.spec});
  final CharacterSpec spec;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: shineGold.withValues(alpha: .5), width: 1.4),
      boxShadow: [
        BoxShadow(color: shineGold.withValues(alpha: .26),
            blurRadius: 44, spreadRadius: -6),
        BoxShadow(color: Colors.black.withValues(alpha: .5),
            blurRadius: 24, offset: const Offset(0, 14)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26.6),
      child: Stack(fit: StackFit.expand, children: [
        Portrait(spec, radius: 0, border: false),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          stops: const [.5, 1],
          colors: [Colors.transparent, Colors.black.withValues(alpha: .92)],
        ))),
        Positioned(left: 22, right: 22, bottom: 22, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const StatPill('TOKOH SOROTAN', icon: Icons.star_rounded,
                color: shineGold),
            const SizedBox(height: 10),
            Text(spec.name, style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, height: 1.1)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatPill('HP ${spec.hp}', icon: Icons.favorite, color: shineJade),
              StatPill('ATK ${spec.attack}', icon: Icons.bolt, color: shineEmber),
              StatPill(spec.skill, icon: Icons.auto_awesome, color: shineViolet),
            ]),
          ],
        )),
      ]),
    ),
  );
}

// ───────────── Lembar Arena Online ─────────────

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
