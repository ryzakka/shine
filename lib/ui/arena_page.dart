import 'dart:math' as math;
import 'dart:async';
import '../game/bot_player.dart';
import '../game/saved_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../domain/battle_rules.dart';
import '../online/shine_service.dart';
import 'shine_ui.dart';

typedef BattleAction = Future<void> Function({
required int attack, required int defend, required int reserve,
required bool useSkill, int? swapTo,
});

Map<String, dynamic> localSnapshot(LocalBattle battle) => {
  'turn': battle.turn,
  'winner': battle.winner,
  'log': battle.log,
  'teams': [for (final team in battle.teams) {
    'active': team.active, 'reserve': team.reserve, 'block': team.block,
    'cards': [for (final unit in team.fighters) {
      'id': unit.spec.id, 'hp': unit.hp, 'max_hp': unit.spec.hp,
      'atk': unit.spec.attack, 'cd': unit.cooldown,
    }],
  }],
};

class LocalArenaPage extends StatefulWidget {
  const LocalArenaPage({super.key, required this.battle,
    this.againstBot = false, this.difficulty = 1});
  final LocalBattle battle;
  final bool againstBot;
  final int difficulty;
  @override
  State<LocalArenaPage> createState() => _LocalArenaPageState();
}

class _LocalArenaPageState extends State<LocalArenaPage> {
  Timer? _botTimer;
  bool _resultRecorded = false;
  late final ShineBot _bot = ShineBot(difficulty: widget.difficulty);

  @override
  void initState() {
    super.initState();
    widget.battle.addListener(_stateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _stateChanged());
  }

  void _stateChanged() {
    if (!mounted) return;
    LocalGameStorage.save(widget.battle,
        againstBot: widget.againstBot, difficulty: widget.difficulty);
    if (widget.battle.winner != null && !_resultRecorded) {
      _resultRecorded = true;
      LocalGameStorage.recordResult(againstBot: widget.againstBot,
          winner: widget.battle.winner!);
    }
    if (widget.againstBot && widget.battle.winner == null &&
        widget.battle.acting == 1 && _botTimer == null) {
      _botTimer = Timer(const Duration(milliseconds: 1100), () {
        _botTimer = null;
        if (!mounted || widget.battle.acting != 1 || widget.battle.winner != null) return;
        final action = _bot.choose(widget.battle);
        widget.battle.act(attack: action.attack, defend: action.defend,
            reserve: action.reserve, skill: action.skill, swapTo: action.swapTo);
      });
    }
  }

  Future<void> _stopLocal() async {
    final agreed = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(title: const Text('Hentikan pertandingan?'),
            content: const Text('Pertandingan lokal ini akan dihapus dan tidak dapat dilanjutkan.'),
            actions: [
              TextButton(onPressed:() => Navigator.pop(ctx,false),child:const Text('Batal')),
              FilledButton(onPressed:() => Navigator.pop(ctx,true),child:const Text('Hentikan')),
            ]));
    if (agreed != true) return;
    _botTimer?.cancel();
    await LocalGameStorage.remove();
    if (mounted) Navigator.pop(context);
  }

  void _playAgain() {
    final a = widget.battle.teams[0].fighters.map((f) => f.spec.id).toList();
    final b = widget.battle.teams[1].fighters.map((f) => f.spec.id).toList();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LocalArenaPage(
        battle: LocalBattle(teamA: a, teamB: b),
        againstBot: widget.againstBot,
        difficulty: widget.difficulty,
      ),
    ));
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    widget.battle.removeListener(_stateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.battle,
    builder: (context, _) => MatchArena(
      state: localSnapshot(widget.battle),
      title: widget.againstBot ? 'Shine • Vs Komputer' : 'Shine • Dua Pemain',
      viewerSide: widget.againstBot ? 0 : widget.battle.acting,
      isBotMatch: widget.againstBot,
      history: widget.battle.history,
      onReplay: _playAgain,
      turnDeadline: widget.battle.turnDeadlineUtc,
      onTimeout: () async => widget.battle.skipTimedOutTurn(),
      onExit: () => Navigator.pop(context),
      onStopLocal: _stopLocal,
      canAct: !widget.againstBot || widget.battle.acting == 0,
      onAction: ({int attack = 0, int defend = 0,
        int reserve = 0, bool useSkill = false, int? swapTo}) async {
        widget.battle.act(attack: attack, defend: defend,
            reserve: reserve, skill: useSkill, swapTo: swapTo);
      },
    ),
  );
}

class OnlineArenaPage extends StatefulWidget {
  const OnlineArenaPage({super.key, required this.roomId, required this.roomCode});
  final String roomId;
  final String roomCode;
  @override
  State<OnlineArenaPage> createState() => _OnlineArenaPageState();
}

class _OnlineArenaPageState extends State<OnlineArenaPage> {
  late final ShineService service = ShineService(Supabase.instance.client);
  late final Stream<List<Map<String, dynamic>>> roomStream = service.watchRoom(widget.roomId);
  bool submitting = false;
  bool expiring = false;

  void _notice(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tindakan gagal: $error')));
  }

  Future<bool> _perform(Future<void> Function() action) async {
    if (submitting) return false;
    setState(() => submitting = true);
    try {
      await action();
      return true;
    } catch (error) {
      _notice(error);
      return false;
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<bool> _ask(String title, String body, String confirm) async {
    if (!mounted) return false;
    return await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title), content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
          ],
        )) ?? false;
  }

  Future<void> _endRoom({required bool disband}) async {
    final agreed = await _ask(disband ? 'Bubarkan ruang?' : 'Menyerah?',
        disband
            ? 'Semua pemain akan keluar dari pertandingan. Tidak ada pemenang.'
            : 'Pertandingan berakhir dan tim lawan dinyatakan menang.',
        disband ? 'Bubarkan' : 'Menyerah');
    if (agreed) await _perform(() => service.endRoom(widget.roomId, disband: disband));
  }

  Future<void> _expire() async {
    if (expiring) return;
    expiring = true;
    try { await service.expireTurn(widget.roomId); }
    catch (error) { _notice(error); }
    finally { expiring = false; }
  }

  Widget _centerScaffold({required String title, required IconData icon,
    required String message, String? action, bool spinner = false}) =>
      ShineScaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Padding(padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (spinner) const CircularProgressIndicator()
              else Icon(icon, color: shineGold, size: 64),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.4)),
              if (action != null) ...[
                const SizedBox(height: 22),
                SizedBox(width: 240, child: ShineButton(label: action,
                    icon: Icons.home_outlined, onPressed: () => Navigator.pop(context))),
              ],
            ]))),
      );

  Widget _lobby(Map<String,dynamic> room) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isHost = uid == room['host_id'];
    final joined = room['guest_id'] != null;
    final ready = room['guest_ready'] == true;
    final seconds = (room['turn_seconds'] as num?)?.toInt() ?? 30;
    final hostCards = (room['host_cards'] as List? ?? []).map((e) => e.toString()).toList();
    final guestCards = (room['guest_cards'] as List? ?? []).map((e) => e.toString()).toList();
    return ShineScaffold(
      appBar: AppBar(title: const Text('LOBI SHINE'), actions: [
        IconButton(tooltip:'Beranda (ruang tetap ada)',
            onPressed: () => Navigator.pop(context), icon: const Icon(Icons.home_outlined)),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), children: [
        Reveal(child: ShinePanel(glow: shineGold, borderColor: shineGold.withValues(alpha: .5),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(children: [
              const Text('KODE UNDANGAN', style: TextStyle(letterSpacing: 3,
                  fontSize: 11, color: shineMuted, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                    colors: [shineGoldLight, shineGold, shineGoldDeep],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
                child: SelectableText(widget.roomCode, style: const TextStyle(
                    color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 10)),
              ),
              TextButton.icon(onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.roomCode));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kode lobi disalin.')));
              }, icon: const Icon(Icons.copy, size: 18), label: const Text('Salin kode')),
            ]))),
        const SizedBox(height: 16),
        Reveal(index: 1, child: _lobbyPlayer('TIM A • HOST', hostCards,
            joined: true, ready: true, accent: shineAzure)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(
            child: Text('VS', style: TextStyle(color: shineGold.withValues(alpha: .9),
                fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 4)))),
        Reveal(index: 2, child: _lobbyPlayer('TIM B • PEMAIN KEDUA', guestCards,
            joined: joined, ready: ready, accent: shineEmber)),
        SectionLabel('TIMER PER GILIRAN', trailing: StatPill('$seconds detik',
            icon: Icons.timer_outlined, color: shineGold)),
        Wrap(spacing:8,runSpacing:8,children: [
          for (final time in const [20,30,45,60])
            ChoiceChip(label: Text('$time detik'), selected: seconds == time,
                onSelected: isHost && !submitting
                    ? (_) => _perform(() => service.setTimer(widget.roomId,time))
                    : null),
        ]),
        const SizedBox(height: 24),
        if (isHost) ...[
          ShineButton(icon: Icons.play_arrow, label: 'MULAI PERTANDINGAN', height: 60,
              onPressed: joined && ready && !submitting
                  ? () => _perform(() => service.startRoom(widget.roomId)) : null),
          const SizedBox(height: 10),
          Text(joined
              ? (ready ? 'Pemain kedua siap. Pertandingan dapat dimulai.'
              : 'Menunggu pemain kedua menekan tombol Siap.')
              : 'Menunggu pemain kedua masuk menggunakan kode di atas.',
              textAlign: TextAlign.center, style: const TextStyle(color:shineMuted,fontSize:12)),
        ] else ...[
          ShineButton(height: 60, primary: !ready,
              icon: ready ? Icons.check_circle : Icons.hourglass_bottom,
              label: ready ? 'SUDAH SIAP • BATALKAN' : 'SAYA SIAP',
              onPressed: submitting ? null : () => _perform(() => service.setReady(widget.roomId,!ready))),
          const SizedBox(height: 10),
          const Text('Setelah kedua pemain siap, host akan memulai pertandingan.',
              textAlign: TextAlign.center, style: TextStyle(color:shineMuted,fontSize:12)),
        ],
        const SizedBox(height: 26),
        ShineButton(primary: false, icon: Icons.home_outlined, height: 48,
            label: 'KEMBALI KE BERANDA', subtitle: 'Lobi tetap ada',
            onPressed: () => Navigator.pop(context)),
        const SizedBox(height: 4),
        TextButton.icon(onPressed: submitting ? null : () async {
          if (isHost) {
            await _endRoom(disband: true);
          } else if (await _ask('Keluar dari lobi?',
              'Slot tim B akan dibuka kembali untuk pemain lain.', 'Keluar')) {
            final success = await _perform(() => service.leaveLobby(widget.roomId));
            if (success && mounted) Navigator.pop(context);
          }
        }, style: TextButton.styleFrom(foregroundColor: shineEmber),
            icon: Icon(isHost ? Icons.delete_outline : Icons.exit_to_app),
            label: Text(isHost ? 'Bubarkan lobi' : 'Keluar dari lobi')),
      ])),
    );
  }

  Widget _lobbyPlayer(String label, List<String> ids,
      {required bool joined, required bool ready, required Color accent}) =>
      ShinePanel(tint: accent, borderColor: ready ? shineJade.withValues(alpha: .6) : null,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: TextStyle(color: accent,
                  fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.4))),
              !joined
                  ? const StatPill('Belum bergabung', icon: Icons.person_off_outlined)
                  : ready
                  ? const StatPill('Siap', icon: Icons.check_circle, color: shineJade)
                  : const StatPill('Belum siap', icon: Icons.hourglass_bottom, color: shineGold),
            ]),
            const SizedBox(height: 12),
            SizedBox(height: 128, child: Row(children: [
              for (var i = 0; i < 3; i++) Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: i < ids.length
                    ? Column(children: [
                  Expanded(child: Portrait(characterById(ids[i]), radius: 12)),
                  const SizedBox(height: 5),
                  Text(characterById(ids[i]).name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ])
                    : DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12)),
                    child: const Center(child: Icon(Icons.help_outline, color: Colors.white24))),
              )),
            ])),
          ]));

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: roomStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _centerScaffold(title: 'ONLINE',
          icon: Icons.error_outline, message: 'Gagal memuat ruang: ${snapshot.error}',
          action: 'KE BERANDA');
      if (!snapshot.hasData) return _centerScaffold(title: 'ONLINE',
          icon: Icons.hourglass_bottom, message: 'Memuat ruang…', spinner: true);
      if (snapshot.data!.isEmpty) return _centerScaffold(title: 'ONLINE',
          icon: Icons.meeting_room_outlined,
          message: 'Ruang tidak tersedia atau kamu sudah keluar.', action: 'KE BERANDA');
      final room = snapshot.data!.first;
      final status = room['status'] as String? ?? '';
      if (status == 'waiting') return _lobby(room);
      if (status == 'closed') return _centerScaffold(title: 'RUANG DIBUBARKAN',
          icon: Icons.meeting_room_outlined,
          message: 'Ruang telah dibubarkan oleh host.', action: 'KEMBALI KE BERANDA');
      final rawState = room['state'];
      if (rawState is! Map) return _centerScaffold(title: 'ONLINE',
          icon: Icons.hourglass_bottom, message: 'Menunggu status pertandingan…', spinner: true);
      final state = Map<String, dynamic>.from(rawState);
      final acting = ((state['turn'] as num).toInt()-1)%2;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final isHost = uid == room['host_id'];
      final canAct = acting == 0 ? isHost : uid == room['guest_id'];
      final deadlineString = room['turn_deadline'] as String?;
      return MatchArena(
        title: 'Online • ${widget.roomCode}', state: state,
        viewerSide: isHost ? 0 : 1,
        canAct: canAct && !submitting && status == 'playing',
        turnDeadline: deadlineString == null ? null : DateTime.tryParse(deadlineString)?.toUtc(),
        onTimeout: status == 'playing' ? _expire : null,
        onExit: () => Navigator.pop(context),
        onSurrender: status == 'playing' && !submitting
            ? () => _endRoom(disband:false) : null,
        onDisband: status == 'playing' && isHost && !submitting
            ? () => _endRoom(disband:true) : null,
        onAction: ({int attack = 0, int defend = 0,
          int reserve = 0, bool useSkill = false, int? swapTo}) async {
          await _perform(() => service.submit(
            id: widget.roomId,
            revision: (room['revision'] as num).toInt(),
            attack: attack, defend: defend, reserve: reserve,
            useSkill: useSkill, swapTo: swapTo,
          ));
        },
      );
    },
  );
}

class MatchArena extends StatefulWidget {
  const MatchArena({super.key, required this.state, required this.title,
    required this.canAct, required this.onAction,
    required this.viewerSide, this.isBotMatch = false,
    this.history = const [], this.onReplay,
    this.turnDeadline, this.onTimeout, this.onExit,
    this.onSurrender, this.onDisband, this.onStopLocal});
  final int viewerSide;
  final bool isBotMatch;
  final List<String> history;
  final VoidCallback? onReplay;
  final DateTime? turnDeadline;
  final Future<void> Function()? onTimeout;
  final VoidCallback? onExit;
  final Future<void> Function()? onSurrender;
  final Future<void> Function()? onDisband;
  final Future<void> Function()? onStopLocal;
  final Map<String, dynamic> state;
  final String title;
  final bool canAct;
  final BattleAction onAction;
  @override
  State<MatchArena> createState() => _MatchArenaState();
}

class _MatchArenaState extends State<MatchArena> {
  int attack = 0, defend = 0, reserve = 0;
  bool skill = false, busy = false;
  Timer? _countdown;
  bool _timeoutNotified = false;
  DateTime? _lastTimeoutAttempt;
  int _turnTotal = 30;
  int get remainingSeconds => widget.turnDeadline == null ? 0 : math.max(0,
      (widget.turnDeadline!.difference(DateTime.now().toUtc()).inMilliseconds / 1000).ceil());
  int get turn => (widget.state['turn'] as num).toInt();
  int get activeSide => (turn-1)%2;
  List<dynamic> get teams => widget.state['teams'] as List<dynamic>;
  Map<String,dynamic> get own => Map<String,dynamic>.from(teams[activeSide] as Map);
  Map<String,dynamic> get ownCard => Map<String,dynamic>.from((own['cards'] as List)[(own['active'] as num).toInt()] as Map);
  CharacterSpec get spec => characterById(ownCard['id'] as String);
  int get available => math.min(8, math.min(turn,4)+(own['reserve'] as num).toInt());
  int get spent => attack+defend+reserve+(skill ? spec.cost : 0);
  int get foeBlock => (Map<String,dynamic>.from(teams[1-activeSide] as Map)['block'] as num).toInt();
  bool get _offensive => const {'damage','pierce','recoil','conditional_damage','hybrid'}.contains(spec.kind);
  bool get _personal => widget.isBotMatch || widget.onReplay == null;

  void reset() {
    skill=false; defend=0;
    reserve=math.min(4,math.max(0,available-1));
    attack=available-reserve;
  }

  @override
  void initState() {
    super.initState();
    reset();
    _turnTotal = math.max(1, remainingSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      final retryAllowed = _lastTimeoutAttempt == null ||
          now.difference(_lastTimeoutAttempt!) >= const Duration(seconds: 5);
      if (widget.state['winner'] == null && widget.turnDeadline != null &&
          remainingSeconds == 0 && widget.onTimeout != null &&
          (!_timeoutNotified || retryAllowed)) {
        _timeoutNotified = true;
        _lastTimeoutAttempt = now;
        widget.onTimeout!();
      }
      setState(() {});
    });
  }
  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }
  @override
  void didUpdateWidget(covariant MatchArena oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state['turn']!=widget.state['turn']) reset();
    if (oldWidget.turnDeadline != widget.turnDeadline ||
        oldWidget.state['turn'] != widget.state['turn']) {
      _timeoutNotified = false;
      _lastTimeoutAttempt = null;
      _turnTotal = math.max(1, remainingSeconds);
    }
  }

  Future<void> submit({int? swapTo}) async {
    if (busy) return;
    setState(() => busy=true);
    try {
      if (swapTo != null) {
        await widget.onAction(attack:0, defend:0, reserve:0,
            useSkill:false, swapTo:swapTo);
      } else {
        await widget.onAction(attack:attack, defend:defend,
            reserve:reserve, useSkill:skill);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Aksi gagal: $error')));
    } finally {
      if (mounted) setState(() => busy=false);
    }
  }

  Future<void> _confirmSwap(int index) async {
    final fighter = (own['cards'] as List)[index] as Map;
    final name = characterById(fighter['id'] as String).name;
    final approved = await showDialog<bool>(context: context, builder: (context) =>
        AlertDialog(title: const Text('Ganti tokoh?'),
            content: Text('Ganti tokoh aktif ke $name? Pergantian menghabiskan seluruh giliran ini.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ya, ganti'))]));
    if (approved == true && mounted) await submit(swapTo: index);
  }

  // ───────────── Logika bantu tampilan ─────────────

  String? get _issue {
    if (spent != available) {
      return spent > available ? 'Alokasi melebihi PA tersedia.'
          : 'Alokasikan seluruh PA untuk melanjutkan.';
    }
    if (skill && _offensive && attack == 0) {
      return 'Skill ofensif membutuhkan minimal 1 PA serang.';
    }
    if (skill && spec.kind == 'conditional_damage' && spec.aux > 0 && attack < spec.aux) {
      return 'Skill ini membutuhkan minimal ${spec.aux} PA serang.';
    }
    return null;
  }

  int get _previewDamage {
    try {
      var pierce = 0, bonus = 0;
      if (skill) {
        switch (spec.kind) {
          case 'damage':
          case 'recoil':
          case 'hybrid':
            bonus = spec.value;
          case 'conditional_damage':
            if (spec.aux > 0 || foeBlock == 0) bonus = spec.value;
          case 'pierce':
            pierce = spec.value;
        }
      }
      return BattleRules.resolveAttack(attackPoints: attack,
          defenderBlockPoints: foeBlock, attackStat: spec.attack,
          piercingBlockPoints: pierce, bonusDamageOnHit: bonus).damage;
    } catch (_) { return 0; }
  }

  void _toggleSkill(bool on) => setState(() {
    skill = on;
    if (on) {
      var over = spent - available;
      final minAttack = _offensive ? 1 : 0;
      while (over > 0) {
        if (reserve > 0) { reserve--; }
        else if (defend > 0) { defend--; }
        else if (attack > minAttack) { attack--; }
        else { break; }
        over--;
      }
    } else {
      final free = available - spent;
      if (free > 0) attack += free;
    }
  });

  String get _turnLabel {
    if (widget.state['winner'] != null) return 'PERTANDINGAN SELESAI';
    if (_personal) {
      final mine = activeSide == widget.viewerSide;
      if (widget.isBotMatch) return mine ? 'GILIRANMU' : 'GILIRAN KOMPUTER';
      return mine ? 'GILIRANMU' : 'GILIRAN LAWAN';
    }
    return 'GILIRAN TIM ${activeSide == 0 ? 'A' : 'B'}';
  }

  Color get _accent {
    if (widget.state['winner'] != null || !_personal) return shineGold;
    return activeSide == widget.viewerSide ? shineAzure : shineEmber;
  }

  void _showHistory() => showModalBottomSheet<void>(
    context: context, isScrollControlled: true,
    builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RIWAYAT PERTARUNGAN', style: TextStyle(color: shineGold,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              SizedBox(height: 320, child: ListView.builder(
                  reverse: true, itemCount: widget.history.length,
                  itemBuilder: (_, i) {
                    final index = widget.history.length - 1 - i;
                    return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 28, child: Text('${index + 1}', style: const TextStyle(
                              color: shineGold, fontWeight: FontWeight.w900, fontSize: 12))),
                          Expanded(child: Text(widget.history[index], style: TextStyle(
                              fontSize: 13, height: 1.35,
                              color: i == 0 ? Colors.white : Colors.white70))),
                        ]));
                  })),
            ])),
    ),
  );

  // ───────────── Bagian tampilan ─────────────

  Widget _timer() {
    final frac = (remainingSeconds / _turnTotal).clamp(0.0, 1.0);
    final urgent = remainingSeconds <= 10;
    final color = urgent ? shineEmber : shineGold;
    return SizedBox(width: 50, height: 50, child: Stack(fit: StackFit.expand, children: [
      CircularProgressIndicator(value: frac, strokeWidth: 4,
          backgroundColor: Colors.white12, color: color),
      Center(child: Text('$remainingSeconds', style: TextStyle(
          fontWeight: FontWeight.w900, fontSize: 16, color: color))),
    ]));
  }

  Widget _turnBanner() {
    final winner = widget.state['winner'];
    final urgent = winner == null && widget.turnDeadline != null && remainingSeconds <= 10;
    return ShinePanel(
      tint: _accent, radius: 18,
      borderColor: urgent ? shineEmber.withValues(alpha: .8) : _accent.withValues(alpha: .35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GILIRAN $turn', style: const TextStyle(fontSize: 10.5,
              color: shineMuted, letterSpacing: 2.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(_turnLabel, style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w900, letterSpacing: 1.5, color: _accent)),
        ])),
        if (winner == null && widget.turnDeadline != null) _timer(),
      ]),
    );
  }

  Widget _vsAndLog() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(children: [
      Row(children: [
        Expanded(child: Container(height: 1, decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.transparent, shineGold.withValues(alpha: .6)])))),
        Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: shineGold.withValues(alpha: .7)),
                color: shineGold.withValues(alpha: .1)),
            child: const Text('VS', style: TextStyle(color: shineGold,
                fontWeight: FontWeight.w900, letterSpacing: 3))),
        Expanded(child: Container(height: 1, decoration: BoxDecoration(
            gradient: LinearGradient(colors: [shineGold.withValues(alpha: .6), Colors.transparent])))),
      ]),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.history.isEmpty ? null : _showHistory,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Text(widget.state['log'] as String? ?? '',
                    key: ValueKey(widget.state['log']),
                    textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, height: 1.4,
                        color: Colors.white70, fontStyle: FontStyle.italic)))),
      ),
    ]),
  );

  Widget _pips() {
    final colors = <Color>[
      for (var i = 0; i < attack; i++) shineEmber,
      for (var i = 0; i < defend; i++) shineAzure,
      for (var i = 0; i < reserve; i++) shineGold,
      if (skill) for (var i = 0; i < spec.cost; i++) shineViolet,
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < available; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 17, height: 17,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < colors.length ? colors[i] : Colors.transparent,
              border: Border.all(color: i < colors.length ? colors[i] : Colors.white24, width: 1.5),
              boxShadow: i < colors.length
                  ? [BoxShadow(color: colors[i].withValues(alpha: .55), blurRadius: 8)] : null),
        ),
    ]);
  }

  Widget _skillCard(int cd) {
    final ready = cd == 0;
    return Opacity(opacity: ready ? 1 : .55, child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: skill ? shineViolet.withValues(alpha: .16) : Colors.white.withValues(alpha: .04),
          border: Border.all(color: skill ? shineViolet : Colors.white12, width: skill ? 1.6 : 1)),
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: ready ? () => _toggleSkill(!skill) : null,
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Icon(Icons.auto_awesome, color: ready ? shineViolet : shineMuted),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.skill, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Text(skillText(spec), style: const TextStyle(fontSize: 11.5, color: shineMuted, height: 1.35)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatPill('${spec.cost} PA', color: shineGold),
              StatPill('CD ${spec.cooldown}', color: shineGold),
              if (!ready) StatPill('Cooldown $cd giliran', icon: Icons.hourglass_bottom, color: shineEmber),
            ]),
          ])),
          const SizedBox(width: 8),
          Icon(skill ? Icons.check_circle : Icons.circle_outlined,
              color: skill ? shineViolet : Colors.white30),
        ])),
      )),
    ));
  }

  Widget _swapSection(Map<String,dynamic> me, bool canPlay) {
    final cards = me['cards'] as List;
    final active = (me['active'] as num).toInt();
    final options = [for (var i = 0; i < 3; i++)
      if (i != active && (cards[i]['hp'] as num).toInt() > 0) i];
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('GANTI TOKOH • menghabiskan giliran penuh', style: TextStyle(
          fontSize: 11, color: shineMuted, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(children: [
        for (final i in options) Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Opacity(opacity: canPlay ? 1 : .5, child: Material(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: canPlay ? () => _confirmSwap(i) : null,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12)),
                child: Row(children: [
                  Portrait(characterById(cards[i]['id'] as String),
                      width: 32, height: 46, radius: 8),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(characterById(cards[i]['id'] as String).name, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                    Text('${cards[i]['hp']} HP', style: const TextStyle(fontSize: 10, color: shineMuted)),
                  ])),
                  const Icon(Icons.swap_horiz, size: 16, color: shineGold),
                ]),
              ),
            ),
          )),
        )),
      ]),
    ]);
  }

  Widget _actionDock(Map<String,dynamic> me, bool canPlay) {
    final cd = (ownCard['cd'] as num).toInt();
    final issue = _issue;
    final left = available - spent;
    final showSkillError = issue != null && spent == available;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Text('POIN AKSI', style: TextStyle(color: shineGold,
            fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
        const Spacer(),
        StatPill(left == 0 ? 'Siap' : (left > 0 ? '$left PA tersisa' : '${-left} PA berlebih'),
            icon: left == 0 ? Icons.check_circle : Icons.pending_outlined,
            color: left == 0 ? shineJade : shineEmber),
      ]),
      const SizedBox(height: 4),
      Text('Tersedia $available PA • cadangan sebelumnya ${own['reserve']}',
          style: const TextStyle(fontSize: 11, color: shineMuted)),
      const SizedBox(height: 10),
      _pips(),
      const SizedBox(height: 8),
      _ApRow(label: 'Serang', icon: Icons.bolt, color: shineEmber, value: attack,
          hint: attack == 0 ? 'Tanpa serangan' : (foeBlock > 0
              ? 'Perkiraan damage ~$_previewDamage • lawan bertahan $foeBlock'
              : 'Perkiraan damage ~$_previewDamage'),
          onMinus: attack > 0 ? () => setState(() => attack--) : null,
          onPlus: attack < 8 && spent < available ? () => setState(() => attack++) : null),
      _ApRow(label: 'Bertahan', icon: Icons.shield_outlined, color: shineAzure, value: defend,
          hint: 'Menyerap serangan di giliran lawan',
          onMinus: defend > 0 ? () => setState(() => defend--) : null,
          onPlus: defend < 8 && spent < available ? () => setState(() => defend++) : null),
      _ApRow(label: 'Cadangkan', icon: Icons.inventory_2_outlined, color: shineGold, value: reserve,
          hint: 'Dibawa ke giliran berikutnya (maks. 4)',
          onMinus: reserve > 0 ? () => setState(() => reserve--) : null,
          onPlus: reserve < 4 && spent < available ? () => setState(() => reserve++) : null),
      const SizedBox(height: 10),
      _skillCard(cd),
      if (showSkillError) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(issue, style: const TextStyle(color: shineEmber, fontSize: 12))),
      if (!showSkillError && issue != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(issue, style: const TextStyle(color: Colors.white54, fontSize: 12))),
      const SizedBox(height: 12),
      ShineButton(icon: Icons.check_circle_outline, label: 'JALANKAN AKSI',
          onPressed: issue == null && canPlay ? () => submit() : null),
      _swapSection(me, canPlay),
    ]);
  }

  Widget _resultPanel(int w) {
    final won = w == widget.viewerSide;
    final bad = _personal && !won;
    final color = bad ? shineEmber : shineGold;
    final title = _personal ? (won ? 'KEMENANGAN' : 'KEKALAHAN')
        : 'TIM ${w == 0 ? 'A' : 'B'} MENANG';
    final sub = !_personal ? 'Pertandingan selesai.'
        : (won ? 'Seluruh tokoh lawan telah tumbang.' : 'Seluruh tokohmu tumbang. Coba strategi lain!');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .8, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Opacity(
          opacity: ((v - .8) * 8).clamp(0.0, 1.0),
          child: Transform.scale(scale: v, child: child)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(bad ? Icons.heart_broken : Icons.emoji_events, color: color, size: 46),
        const SizedBox(height: 6),
        ShaderMask(
            shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color.lerp(color, Colors.white, .5)!, color]).createShader(r),
            child: Text(title, textAlign: TextAlign.center, style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5,
                color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 12)]))),
        const SizedBox(height: 4),
        Text(sub, textAlign: TextAlign.center,
            style: const TextStyle(color: shineMuted, fontSize: 13)),
        const SizedBox(height: 18),
        if (widget.onReplay != null) ...[
          ShineButton(icon: Icons.replay, label: 'MAIN LAGI', onPressed: widget.onReplay),
          const SizedBox(height: 10),
        ],
        ShineButton(primary: widget.onReplay == null, icon: Icons.home_outlined,
            label: 'KEMBALI KE MENU', onPressed: () => Navigator.of(context).pop()),
      ]),
    );
  }

  Widget _waiting() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    const SizedBox(width: 18, height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: shineGold)),
    const SizedBox(width: 12),
    Flexible(child: Text(widget.isBotMatch ? 'Komputer sedang menentukan aksi…'
        : 'Menunggu giliran atau sinkronisasi lawan…',
        style: const TextStyle(color: shineMuted, fontSize: 13))),
  ]);

  @override
  Widget build(BuildContext context) {
    final winner = widget.state['winner'];
    final opponent = Map<String,dynamic>.from(teams[1-widget.viewerSide] as Map);
    final me = Map<String,dynamic>.from(teams[widget.viewerSide] as Map);
    final canPlay = widget.canAct && winner==null && !busy;
    final enemyIdx = 1 - widget.viewerSide;

    final Widget dock;
    if (winner != null) {
      dock = _resultPanel((winner as num).toInt());
    } else if (!widget.canAct) {
      dock = _waiting();
    } else {
      dock = _actionDock(me, canPlay);
    }

    return ShineScaffold(
      accent: _accent,
      appBar: AppBar(title: Text(widget.title), actions: [
        if (widget.onExit != null)
          IconButton(tooltip:'Beranda tanpa mengakhiri pertandingan',
              icon: const Icon(Icons.home_outlined), onPressed: widget.onExit),
        if (widget.history.isNotEmpty)
          IconButton(tooltip: 'Riwayat pertarungan', onPressed: _showHistory,
              icon: const Icon(Icons.history)),
        if (widget.onSurrender != null || widget.onDisband != null || widget.onStopLocal != null)
          PopupMenuButton<String>(tooltip: 'Opsi pertandingan',
              onSelected: (choice) {
                if (choice == 'surrender') widget.onSurrender?.call();
                if (choice == 'disband') widget.onDisband?.call();
                if (choice == 'stop') widget.onStopLocal?.call();
              },
              itemBuilder: (_) => [
                if (widget.onSurrender != null)
                  const PopupMenuItem(value:'surrender', child: Text('Menyerah (lawan menang)')),
                if (widget.onDisband != null)
                  const PopupMenuItem(value:'disband', child: Text('Bubarkan ruang (host)')),
                if (widget.onStopLocal != null)
                  const PopupMenuItem(value:'stop', child: Text('Hentikan pertandingan lokal')),
              ]),
      ]),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 12), children: [
          _turnBanner(),
          const SizedBox(height: 12),
          _FighterPanel(key: ValueKey('team-$enemyIdx'),
              label: 'TIM ${enemyIdx==0?'A':'B'} • ${widget.isBotMatch?'KOMPUTER':'LAWAN'}',
              team: opponent, enemy: true,
              isTurn: winner == null && activeSide == enemyIdx),
          _vsAndLog(),
          _FighterPanel(key: ValueKey('team-${widget.viewerSide}'),
              label: 'TIM ${widget.viewerSide==0?'A':'B'} • ${widget.isBotMatch?'KAMU':'PEMAIN'}',
              team: me, enemy: false,
              isTurn: winner == null && activeSide == widget.viewerSide),
        ])),
        Container(
          decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1727), Color(0xFF110F1B)]),
              border: Border(top: BorderSide(color: _accent.withValues(alpha: .45))),
              boxShadow: [BoxShadow(color: _accent.withValues(alpha: .18),
                  blurRadius: 24, offset: const Offset(0, -6))]),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .52),
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: AnimatedSize(duration: const Duration(milliseconds: 250), child: dock)),
          ),
        ),
      ])),
    );
  }
}

// ───────────── Komponen pertarungan ─────────────

class _RoundBtn extends StatelessWidget {
  const _RoundBtn(this.icon, this.color, this.onTap);
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? Colors.white.withValues(alpha: .05) : color.withValues(alpha: .2),
    shape: const CircleBorder(),
    child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
        child: SizedBox(width: 38, height: 38,
            child: Icon(icon, size: 20, color: onTap == null ? Colors.white24 : color))),
  );
}

class _ApRow extends StatelessWidget {
  const _ApRow({required this.label, required this.hint, required this.icon,
    required this.color, required this.value, this.onMinus, this.onPlus});
  final String label, hint;
  final IconData icon;
  final Color color;
  final int value;
  final VoidCallback? onMinus, onPlus;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Container(width: 40, height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: color.withValues(alpha: .15),
              border: Border.all(color: color.withValues(alpha: .5))),
          child: Icon(icon, size: 20, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: shineMuted)),
      ])),
      _RoundBtn(Icons.remove, color, onMinus),
      SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: color))),
      _RoundBtn(Icons.add, color, onPlus),
    ]),
  );
}

/// Panel tokoh aktif satu tim, dengan efek getar/kilat saat HP berubah.
class _FighterPanel extends StatefulWidget {
  const _FighterPanel({super.key, required this.label, required this.team,
    required this.enemy, required this.isTurn});
  final String label;
  final Map<String,dynamic> team;
  final bool enemy, isTurn;
  @override
  State<_FighterPanel> createState() => _FighterPanelState();
}

class _FighterPanelState extends State<_FighterPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fx = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));
  int _delta = 0;

  static int _active(Map<String,dynamic> team) => (team['active'] as num).toInt();
  static int _hpAt(Map<String,dynamic> team, int i) =>
      ((team['cards'] as List)[i] as Map)['hp'] is num
          ? (((team['cards'] as List)[i] as Map)['hp'] as num).toInt() : 0;

  @override
  void didUpdateWidget(covariant _FighterPanel old) {
    super.didUpdateWidget(old);
    final idx = _active(old.team);
    final d = _hpAt(widget.team, idx) - _hpAt(old.team, idx);
    if (d != 0) {
      _delta = d;
      _fx.forward(from: 0);
      if (d < 0) HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() { _fx.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final cards = team['cards'] as List;
    final active = _active(team);
    final unit = Map<String,dynamic>.from(cards[active] as Map);
    final spec = characterById(unit['id'] as String);
    final hp = (unit['hp'] as num).toInt();
    final maxHp = (unit['max_hp'] as num).toInt();
    final cd = (unit['cd'] as num).toInt();
    final reserve = (team['reserve'] as num).toInt();
    final block = (team['block'] as num).toInt();
    final accent = widget.enemy ? shineEmber : shineAzure;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color.alphaBlend(accent.withValues(alpha: .16), const Color(0xFF262136)),
                const Color(0xFF181525)]),
          border: Border.all(color: accent.withValues(alpha: widget.isTurn ? .9 : .25),
              width: widget.isTurn ? 1.8 : 1),
          boxShadow: [
            if (widget.isTurn) BoxShadow(color: accent.withValues(alpha: .35),
                blurRadius: 26, spreadRadius: -2),
            BoxShadow(color: Colors.black.withValues(alpha: .35),
                blurRadius: 14, offset: const Offset(0, 8)),
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(widget.label, style: TextStyle(color: accent,
              fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w900))),
          if (widget.isTurn) StatPill('BERAKSI', icon: Icons.bolt, color: accent),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedBuilder(animation: _fx, builder: (context, _) {
            final t = _fx.value;
            final hit = _delta < 0;
            final shake = hit ? math.sin(t * math.pi * 7) * (1 - t) * 7 : 0.0;
            final running = t > 0 && t < 1;
            return Transform.translate(offset: Offset(shake, 0),
                child: SizedBox(width: 96, height: 128, child: Stack(fit: StackFit.expand, children: [
                  Portrait(spec, radius: 14),
                  if (running) Positioned.fill(child: IgnorePointer(child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                          color: (hit ? shineEmber : shineJade).withValues(alpha: (1 - t) * .5))))),
                  if (running) Center(child: Opacity(opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.translate(offset: Offset(0, -30 * t),
                          child: Text(_delta > 0 ? '+$_delta' : '$_delta', style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white,
                              shadows: [Shadow(color: Colors.black, blurRadius: 8),
                                Shadow(color: Colors.black, blurRadius: 3)]))))),
                ])));
          }),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            HpBar(hp: hp, maxHp: maxHp),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatPill('ATK ${spec.attack}', icon: Icons.bolt, color: shineEmber),
              StatPill('PA simpan $reserve', icon: Icons.inventory_2_outlined, color: shineGold),
              StatPill('Tameng $block', icon: Icons.shield_outlined, color: shineAzure),
              cd > 0
                  ? StatPill('CD $cd', icon: Icons.hourglass_bottom)
                  : const StatPill('Skill siap', icon: Icons.auto_awesome, color: shineViolet),
            ]),
            const SizedBox(height: 6),
            Text(spec.skill, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: shineMuted)),
          ])),
        ]),
        const SizedBox(height: 10),
        Row(children: [for (var i = 0; i < 3; i++) Expanded(child: Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
            child: _bench(Map<String,dynamic>.from(cards[i] as Map), active == i, accent))),
        ]),
      ]),
    );
  }

  Widget _bench(Map<String,dynamic> fighter, bool active, Color accent) {
    final spec = characterById(fighter['id'] as String);
    final hp = (fighter['hp'] as num).toInt();
    final alive = hp > 0;
    final maxHp = (fighter['max_hp'] as num?)?.toInt() ?? spec.hp;
    return Opacity(opacity: alive ? 1 : .4, child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: .16) : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? accent : Colors.white12)),
      child: Row(children: [
        Portrait(spec, width: 28, height: 40, radius: 7, border: false),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
              value: maxHp == 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0), minHeight: 4,
              backgroundColor: Colors.white12,
              color: hp / maxHp > .3 ? shineJade : shineEmber)),
          const SizedBox(height: 2),
          Text(alive ? '$hp HP' : 'KO', style: const TextStyle(fontSize: 9, color: shineMuted)),
        ])),
      ]),
    ));
  }
}