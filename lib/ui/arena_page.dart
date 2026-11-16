import 'dart:math' as math;
import 'dart:async';
import '../game/bot_player.dart';
import '../game/saved_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../online/shine_service.dart';
import 'home_page.dart';

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

  Widget _lobby(Map<String,dynamic> room) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isHost = uid == room['host_id'];
    final joined = room['guest_id'] != null;
    final ready = room['guest_ready'] == true;
    final seconds = (room['turn_seconds'] as num?)?.toInt() ?? 30;
    final hostCards = (room['host_cards'] as List? ?? []).map((e) => e.toString()).toList();
    final guestCards = (room['guest_cards'] as List? ?? []).map((e) => e.toString()).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('LOBI SHINE'), actions: [
        IconButton(tooltip:'Beranda (ruang tetap ada)',
          onPressed: () => Navigator.pop(context), icon: const Icon(Icons.home_outlined)),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          const Icon(Icons.groups_2_outlined, color: shineGold, size: 52),
          const SizedBox(height: 12),
          const Text('KODE UNDANGAN', style: TextStyle(letterSpacing: 2, fontSize: 11)),
          const SizedBox(height: 8),
          SelectableText(widget.roomCode,
            style: const TextStyle(color:shineGold, fontSize: 36, fontWeight:FontWeight.w900, letterSpacing:6)),
          TextButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.roomCode));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kode lobi disalin.')));
          }, icon: const Icon(Icons.copy), label: const Text('Salin kode')),
        ]))),
        const SizedBox(height: 16),
        _lobbyPlayer('TIM A • HOST', hostCards, joined: true, ready: true),
        const SizedBox(height: 12),
        _lobbyPlayer('TIM B • PEMAIN KEDUA', guestCards, joined: joined, ready: ready),
        const SizedBox(height: 20),
        Text('TIMER PER GILIRAN  •  $seconds DETIK',
          style: const TextStyle(color:shineGold,fontWeight:FontWeight.w800,fontSize:12)),
        const SizedBox(height: 12),
        Wrap(spacing:8,runSpacing:8,children: [
          for (final time in const [20,30,45,60])
            ChoiceChip(label: Text('$time detik'), selected: seconds == time,
              onSelected: isHost && !submitting
                ? (_) => _perform(() => service.setTimer(widget.roomId,time))
                : null),
        ]),
        const SizedBox(height: 22),
        if (isHost) ...[
          FilledButton.icon(onPressed: joined && ready && !submitting
              ? () => _perform(() => service.startRoom(widget.roomId)) : null,
            icon: const Icon(Icons.play_arrow), label: const Text('MULAI PERTANDINGAN')),
          const SizedBox(height: 10),
          Text(joined
            ? (ready ? 'Pemain kedua siap. Pertandingan dapat dimulai.'
                     : 'Menunggu pemain kedua menekan tombol Siap.')
            : 'Menunggu pemain kedua masuk menggunakan kode di atas.',
            textAlign: TextAlign.center, style: const TextStyle(color:shineMuted,fontSize:12)),
        ] else ...[
          FilledButton.icon(onPressed: submitting
            ? null : () => _perform(() => service.setReady(widget.roomId,!ready)),
            icon: Icon(ready ? Icons.check_circle : Icons.hourglass_bottom),
            label: Text(ready ? 'SUDAH SIAP • BATALKAN' : 'SAYA SIAP')),
          const SizedBox(height: 10),
          const Text('Setelah kedua pemain siap, host akan memulai pertandingan.',
            textAlign: TextAlign.center, style: TextStyle(color:shineMuted,fontSize:12)),
        ],
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.home_outlined),
          label: const Text('Kembali ke beranda (lobi tetap ada)')),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: submitting ? null : () async {
          if (isHost) {
            await _endRoom(disband: true);
          } else if (await _ask('Keluar dari lobi?',
              'Slot tim B akan dibuka kembali untuk pemain lain.', 'Keluar')) {
            final success = await _perform(() => service.leaveLobby(widget.roomId));
            if (success && mounted) Navigator.pop(context);
          }
        }, icon: Icon(isHost ? Icons.delete_outline : Icons.exit_to_app),
          label: Text(isHost ? 'Bubarkan lobi' : 'Keluar dari lobi')),
      ])),
    );
  }

  Widget _lobbyPlayer(String label, List<String> ids,
      {required bool joined, required bool ready}) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label,
            style: const TextStyle(color:shineGold,fontWeight:FontWeight.w800,fontSize:12))),
          Text(!joined ? 'Belum bergabung' : (ready ? 'Siap' : 'Belum siap'),
            style: TextStyle(color:ready ? Colors.greenAccent : shineMuted,fontSize:11)),
        ]),
        const SizedBox(height: 10),
        if (ids.isEmpty) const Text('Menunggu pilihan tiga tokoh...',
          style: TextStyle(color:shineMuted,fontSize:12)),
        if (ids.isNotEmpty) SizedBox(height: 105, child: Row(children: [
          for (final id in ids)
            Expanded(child: Padding(padding:const EdgeInsets.symmetric(horizontal:3),
              child: Column(children: [
                Expanded(child: Image.asset('assets/portraits/$id.webp',fit:BoxFit.contain)),
                const SizedBox(height:4),
                Text(characterById(id).name,maxLines:1,overflow:TextOverflow.ellipsis,
                  style: const TextStyle(fontSize:9)),
              ]))),
        ])),
      ])),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: roomStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(appBar: AppBar(title: const Text('Shine • Online')),
        body: Center(child: Text('Gagal memuat ruang: ${snapshot.error}')));
      if (!snapshot.hasData) return const Scaffold(
        body: Center(child: CircularProgressIndicator()));
      if (snapshot.data!.isEmpty) return Scaffold(
        appBar: AppBar(title: const Text('Shine • Online')),
        body: Center(child: Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Ruang tidak tersedia atau kamu sudah keluar.'),
          TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Ke beranda')),
        ])));
      final room = snapshot.data!.first;
      final status = room['status'] as String? ?? '';
      if (status == 'waiting') return _lobby(room);
      if (status == 'closed') return Scaffold(
        appBar: AppBar(title:const Text('RUANG DIBUBARKAN')),
        body: Center(child: Column(mainAxisSize:MainAxisSize.min,children: [
          const Icon(Icons.meeting_room_outlined,color:shineGold,size:65),
          const SizedBox(height:12),
          const Text('Ruang telah dibubarkan oleh host.'),
          const SizedBox(height:18),
          FilledButton(onPressed:()=>Navigator.pop(context),
            child:const Text('Kembali ke beranda')),
        ])));
      final rawState = room['state'];
      if (rawState is! Map) return const Scaffold(
        body:Center(child:Text('Menunggu status pertandingan...')));
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

  void reset() {
    skill=false; defend=0;
    reserve=math.min(4,math.max(0,available-1));
    attack=available-reserve;
  }

  @override
  void initState() {
    super.initState();
    reset();
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

  Widget meter(String label, int value, int maxValue,
      VoidCallback decrement, VoidCallback increment, IconData icon) {
    return Row(children: [
      Icon(icon,size:20,color:shineGold),
      const SizedBox(width: 7),
      Expanded(child: Text(label, style: const TextStyle(fontSize:13,fontWeight:FontWeight.w600))),
      IconButton(onPressed: value>0 ? decrement : null,icon: const Icon(Icons.remove_circle_outline)),
      SizedBox(width:20,child:Text('$value',textAlign: TextAlign.center,
        style: const TextStyle(fontWeight:FontWeight.bold))),
      IconButton(onPressed: value<maxValue && spent<available ? increment:null,
        icon: const Icon(Icons.add_circle_outline)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final winner = widget.state['winner'];
    final opponent = Map<String,dynamic>.from(teams[1-widget.viewerSide] as Map);
    final me = Map<String,dynamic>.from(teams[widget.viewerSide] as Map);
    final cd = (ownCard['cd'] as num).toInt();
    final canPlay = widget.canAct && winner==null && !busy;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title),actions: [
        if (widget.onExit != null)
          IconButton(tooltip:'Beranda tanpa mengakhiri pertandingan',
            icon: const Icon(Icons.home_outlined), onPressed: widget.onExit),
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
        if (widget.history.isNotEmpty)
          IconButton(tooltip: 'Riwayat pertarungan', onPressed: () => showModalBottomSheet<void>(
            context: context, isScrollControlled: true,
            builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('RIWAYAT PERTARUNGAN', style: TextStyle(color: shineGold, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(height: 280, child: ListView.builder(
                  itemCount: widget.history.length,
                  itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text('${i+1}. ${widget.history[i]}', style: const TextStyle(fontSize: 13))),
                )),
              ])),
            ),
          ), icon: const Icon(Icons.history)),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(14), children: [
        Padding(padding: const EdgeInsets.only(bottom:8),
          child: Text('GILIRAN $turn',style: const TextStyle(
            color:shineGold,fontWeight:FontWeight.bold,letterSpacing:1.1))),
        if (winner == null && widget.turnDeadline != null) ...[
          Card(color: remainingSeconds <= 10 ? const Color(0xFF542B38) : null,
            child: Padding(padding: const EdgeInsets.symmetric(vertical:12,horizontal:14),
              child: Row(children: [
                Icon(Icons.timer_outlined, color: remainingSeconds <= 10 ? Colors.redAccent : shineGold),
                const SizedBox(width:9),
                Expanded(child: Text('Timer Tim ${activeSide == 0 ? 'A' : 'B'}',
                  style: const TextStyle(fontWeight:FontWeight.w700))),
                Text('${remainingSeconds}s', style: TextStyle(fontSize:22,fontWeight:FontWeight.w900,
                  color:remainingSeconds<=10?Colors.redAccent:shineGold)),
              ]))),
          const SizedBox(height:8),
        ],
        _teamPanel('TIM ${widget.viewerSide==0?'B':'A'} • ${widget.isBotMatch?'KOMPUTER':'LAWAN'}',opponent, highlighted:false),
        const Padding(padding: EdgeInsets.symmetric(vertical:13), child: Row(
          children:[Expanded(child:Divider()),Padding(padding:EdgeInsets.symmetric(horizontal:12),
            child:Text('VS',style:TextStyle(color:shineGold,fontWeight:FontWeight.w900,fontSize:18))),Expanded(child:Divider())])),
        _teamPanel('TIM ${widget.viewerSide==0?'A':'B'} • ${widget.isBotMatch?'KAMU':'PEMAIN'}',me,highlighted:true),
        const SizedBox(height:15),
        Card(child: Padding(padding: const EdgeInsets.all(13),
          child: Text(widget.state['log'] as String? ?? '',style: const TextStyle(fontSize:12)))),
        if (winner != null) ...[
          const SizedBox(height:10),
          Center(child: Text(widget.isBotMatch
            ? ((winner as num).toInt() == 0 ? 'KAMU MENANG!' : 'KOMPUTER MENANG!')
            : 'TIM ${(winner as num).toInt()==0?'A':'B'} MENANG!',
            style: const TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:shineGold))),
          const SizedBox(height: 12),
          if (widget.onReplay != null)
            FilledButton.icon(onPressed: widget.onReplay,
              icon: const Icon(Icons.replay), label: const Text('Main lagi')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.home_outlined), label: const Text('Kembali ke menu')),
        ] else if (!canPlay) ...[
          Center(child: Padding(padding: const EdgeInsets.all(20),
            child: Text(widget.isBotMatch ? 'Komputer sedang menentukan aksi…'
              : 'Menunggu giliran atau sinkronisasi lawan…',textAlign:TextAlign.center))),
        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment:CrossAxisAlignment.stretch,
            children: [
              Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                const Text('ALOKASI POIN AKSI',style:TextStyle(color:shineGold,fontWeight:FontWeight.bold)),
                Text('${available-spent} PA tersisa',style:TextStyle(
                  color:spent==available?Colors.greenAccent:Colors.orangeAccent)),
              ]),
              const SizedBox(height:5),
              Text('PA tersedia: $available • cadangan sebelumnya: ${own['reserve']}'),
              const Divider(height:22),
              meter('Serang',attack,8,()=>setState(()=>attack--),()=>setState(()=>attack++),Icons.bolt),
              meter('Bertahan',defend,8,()=>setState(()=>defend--),()=>setState(()=>defend++),Icons.shield_outlined),
              meter('Cadangkan',reserve,4,()=>setState(()=>reserve--),()=>setState(()=>reserve++),Icons.inventory_2_outlined),
              const Divider(height:24),
              SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,
                value:skill,
                title: Text(spec.skill, style:const TextStyle(fontWeight:FontWeight.w600)),
                subtitle: Text('Skill aktif • ${spec.cost} PA • CD ${spec.cooldown} • sisa CD $cd',
                  style:const TextStyle(fontSize:11)),
                onChanged: cd==0 ? (value) => setState(() => skill=value) : null,
              ),
              if (spent>available) const Text('Alokasi melebihi PA tersedia.',
                style:TextStyle(color:Colors.orangeAccent,fontSize:12)),
              if (spent<available) const Text('Alokasikan seluruh PA untuk melanjutkan.',
                style:TextStyle(color:Colors.white60,fontSize:12)),
              const SizedBox(height:10),
              FilledButton.icon(onPressed: spent==available && canPlay ? () => submit() : null,
                icon:const Icon(Icons.check_circle_outline),label:const Text('Jalankan aksi')),
              const SizedBox(height:12),
              const Text('PERGANTIAN TOKOH — menghabiskan giliran penuh',
                style:TextStyle(fontWeight:FontWeight.bold,fontSize:12,color:shineGold)),
              const SizedBox(height:6),
              for (var i=0;i<3;i++)
                if (i!=(me['active'] as num).toInt() &&
                    ((me['cards'] as List)[i]['hp'] as num).toInt()>0)
                  TextButton.icon(onPressed:canPlay ? () => _confirmSwap(i) : null,
                    icon:const Icon(Icons.swap_horiz),label:Text(
                      'Ganti ke ${characterById((me['cards'] as List)[i]['id'] as String).name}')),
            ],
          ))),
        ],
      ])),
    );
  }

  Widget _teamPanel(String title, Map<String,dynamic> team,
      {required bool highlighted}) {
    final cards = team['cards'] as List;
    final active = (team['active'] as num).toInt();
    final unit = Map<String,dynamic>.from(cards[active] as Map);
    final spec = characterById(unit['id'] as String);
    final hp = (unit['hp'] as num).toInt();
    final maxHp = (unit['max_hp'] as num).toInt();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:TextStyle(color:highlighted?shineGold:Colors.white70,
        fontSize:11,letterSpacing:1.5,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _portrait(spec,height:190,width:128),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(spec.name,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          Text('HP $hp / $maxHp',style:const TextStyle(fontSize:12)),
          const SizedBox(height:6),
          ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(
            value:hp/maxHp, minHeight:9,backgroundColor:Colors.white12,
            valueColor:AlwaysStoppedAnimation(hp/maxHp>.30?Colors.greenAccent:Colors.redAccent))),
          const SizedBox(height:12),
          Text('ATK ${spec.attack}  •  CD ${(unit['cd'] as num).toInt()}',
            style:const TextStyle(fontSize:13)),
          Text('Skill: ${spec.skill}',style:const TextStyle(fontSize:11,color:Colors.white70)),
          const SizedBox(height:9),
          Text('PA cadangan ${team['reserve']}  •  pertahanan ${team['block']}',
            style:const TextStyle(fontSize:11,color:shineGold)),
        ])),
      ]),
      const SizedBox(height:10),
      Row(children:[for (var i=0;i<3;i++) Expanded(child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:3),
        child:_smallFighter(Map<String,dynamic>.from(cards[i] as Map),active==i))),
      ]),
    ]);
  }

  Widget _portrait(CharacterSpec spec,{double height=100,double width=68}) =>
    ClipRRect(borderRadius:BorderRadius.circular(10),child:Container(
      decoration:BoxDecoration(border:Border.all(color:shineGold,width:1.4),
        borderRadius:BorderRadius.circular(10)),
      child:Image.asset(spec.asset,height:height,width:width,fit:BoxFit.cover),
    ));

  Widget _smallFighter(Map<String,dynamic> fighter,bool active) {
    final spec = characterById(fighter['id'] as String);
    final alive = (fighter['hp'] as num).toInt()>0;
    return Opacity(opacity:alive?1:.35,child:Container(
      padding:const EdgeInsets.all(6),
      decoration:BoxDecoration(color:active?const Color(0xFF403229):const Color(0xFF231E2B),
        borderRadius:BorderRadius.circular(10),
        border:Border.all(color:active?shineGold:Colors.white12)),
      child:Row(children:[
        Image.asset(spec.asset,width:28,height:44,fit:BoxFit.cover),
        const SizedBox(width:5),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(spec.name,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10)),
          Text('${fighter['hp']} HP',style:const TextStyle(fontSize:10,color:Colors.white70)),
        ])),
      ]),
    ));
  }
}
