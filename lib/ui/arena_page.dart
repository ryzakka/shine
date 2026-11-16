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

typedef RoomMap = Map<String, dynamic>;
typedef RoomList = List<RoomMap>;
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
      _botTimer = Timer(const Duration(milliseconds: 1150), () {
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
    Navigator.of(context).pushReplacement(shineRoute<void>(
      LocalArenaPage(
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
  late final Stream<RoomList> roomStream = service.watchRoom(widget.roomId);
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
  embers: true,
  appBar: AppBar(title: const Text('LOBI ARENA'), actions: [
  IconButton(tooltip:'Beranda (ruang tetap ada)',
  onPressed: () => Navigator.pop(context), icon: const Icon(Icons.home_outlined)),
  ]),
  body: SafeArea(child: Center(child: ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 620),
  child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
  Reveal(child: Column(children: [
  const Text('KODE UNDANGAN RUANG', style: TextStyle(letterSpacing: 3.5,
  fontSize: 10.5, color: shineMuted, fontWeight: FontWeight.w900)),
  const SizedBox(height: 6),
  ShaderMask(
  shaderCallback: (r) => const LinearGradient(
  colors: [shineGoldLight, shineGold, shineGoldDeep],
  begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
  child: SelectableText(widget.roomCode, style: const TextStyle(
  color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 12)),
  ),
  TextButton.icon(onPressed: () async {
  await Clipboard.setData(ClipboardData(text: widget.roomCode));
  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Kode lobi disalin.')));
  }, icon: const Icon(Icons.copy_rounded, size: 16), label: const Text('Salin kode')),
  ])),
  const SizedBox(height: 16),
  Reveal(index: 1, child: _lobbyPlayer('TIM A • HOST', hostCards,
  joined: true, ready: true, accent: shineAzure)),
  Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Center(
  child: Text('VS', style: TextStyle(color: shineGold.withValues(alpha: .9),
  fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 5)))),
  Reveal(index: 2, child: _lobbyPlayer('TIM B • PENANTANG', guestCards,
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
  ShineButton(icon: Icons.play_arrow_rounded, label: 'MULAI PERTANDINGAN', height: 58,
  onPressed: joined && ready && !submitting
  ? () => _perform(() => service.startRoom(widget.roomId)) : null),
  const SizedBox(height: 10),
  Text(joined
  ? (ready ? 'Pemain kedua siap. Pertandingan dapat dimulai.'
      : 'Menunggu pemain kedua menekan tombol Siap.')
      : 'Menunggu pemain kedua masuk menggunakan kode di atas.',
  textAlign: TextAlign.center, style: const TextStyle(color:shineMuted,fontSize:12)),
  ] else ...[
  ShineButton(height: 58, primary: !ready,
  icon: ready ? Icons.check_circle : Icons.hourglass_bottom,
  label: ready ? 'SUDAH SIAP • BATALKAN' : 'SAYA SIAP BERTARUNG',
  onPressed: submitting ? null : () => _perform(() => service.setReady(widget.roomId,!ready))),
  const SizedBox(height: 10),
  const Text('Setelah kedua pemain siap, host akan memulai pertandingan.',
  textAlign: TextAlign.center, style: TextStyle(color:shineMuted,fontSize:12)),
  ],
  const SizedBox(height: 22),
  Row(children: [
  Expanded(child: ShineButton(primary: false, icon: Icons.home_outlined, height: 48,
  label: 'KE BERANDA', onPressed: () => Navigator.pop(context))),
  const SizedBox(width: 12),
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
  label: Text(isHost ? 'Bubarkan' : 'Keluar')),
  ]),
  ])))),
  );
  }

  Widget _lobbyPlayer(String label, List<String> ids,
  {required bool joined, required bool ready, required Color accent}) =>
  ShinePanel(tint: accent, borderColor: ready ? shineJade.withValues(alpha: .5) : null,
  padding: const EdgeInsets.all(14),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Row(children: [
  Expanded(child: Text(label, style: TextStyle(color: accent,
  fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 1.6))),
  !joined
  ? const StatPill('Menunggu pemain', icon: Icons.person_off_outlined)
      : ready
  ? const StatPill('Siap', icon: Icons.check_circle, color: shineJade)
      : const StatPill('Belum siap', icon: Icons.hourglass_bottom, color: shineGold),
  ]),
  const SizedBox(height: 12),
  SizedBox(height: 124, child: Row(children: [
  for (var i = 0; i < 3; i++) Expanded(child: Padding(
  padding: const EdgeInsets.symmetric(horizontal: 4),
  child: i < ids.length
  ? Column(children: [
  Expanded(child: Portrait(characterById(ids[i]), radius: 12)),
  const SizedBox(height: 5),
  Text(characterById(ids[i]).name, maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
  ])
      : DecoratedBox(
  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .025),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: Colors.white12)),
  child: const Center(child: Icon(Icons.help_outline, color: Colors.white24))),
  )),
  ])),
  ]));

  @override
  Widget build(BuildContext context) => StreamBuilder<RoomList>(
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

// ═════════════════════════════════════════════════════════════════
//  PERTARUNGAN — Open Broadcast HUD & Zero-Jank Command Deck
// ═════════════════════════════════════════════════════════════════

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _frac(double v) => v - v.floorToDouble();

class _Ghost {
  const _Ghost(this.side, this.id, this.ko);
  final int side;
  final String id;
  final bool ko;
}

class _Fx {
  const _Fx({required this.actor, required this.attackPts, required this.defend,
    required this.reserveSaved, required this.damage, required this.absorbed,
    required this.oldBlockTarget, required this.skill, required this.skillName,
    required this.swap, required this.timeout, required this.heal,
    required this.selfDamage, required this.ghosts});
  final int actor, attackPts, defend, reserveSaved, damage, absorbed,
      oldBlockTarget, heal, selfDamage;
  final bool skill, swap, timeout;
  final String skillName;
  final List<_Ghost> ghosts;
  int get target => 1 - actor;
  bool get attacked => attackPts > 0 && !swap && !timeout;
  bool get passive => !attacked && !swap && !timeout;
  double get intensity => math.max(.2, attackPts / 8);
}

class _Pose {
  const _Pose({this.dx = 0, this.dy = 0, this.scale = 1, this.rot = 0,
    this.flash = 0, this.flashColor = shineEmber, this.opacity = 1});
  final double dx, dy, scale, rot, flash, opacity;
  final Color flashColor;
}

// ───────────── Latar adegan ─────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.amb, this.accent) : super(repaint: amb);
  final Animation<double> amb;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    final cone = Path()
      ..moveTo(cx - 24, 0)..lineTo(cx + 24, 0)
      ..lineTo(cx + w * .65, h * .76)..lineTo(cx - w * .65, h * .76)..close();
    canvas.drawPath(cone, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [accent.withValues(alpha: .22), accent.withValues(alpha: .01)])
        .createShader(Rect.fromLTWH(0, 0, w, h * .76)));

    final fy = h * .52;
    canvas.drawRect(Rect.fromLTWH(0, fy, w, h - fy), Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: .6)])
        .createShader(Rect.fromLTWH(0, fy, w, h - fy)));
    final grid = Paint()..color = accent.withValues(alpha: .06)..strokeWidth = 1;
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(Offset(cx, fy), Offset(cx + i * w * .24, h), grid);
    }
    for (var i = 1; i <= 4; i++) {
      final y = fy + (h - fy) * (i * i / 16);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    final a = amb.value;
    final rain = Paint()..strokeWidth = 1.05;
    for (var i = 0; i < 46; i++) {
      final x = _frac(i * .6180339) * w;
      final y = _frac(i * .7549 + a * (2 + i % 3)) * h;
      rain.color = const Color(0xFFBFD8FF).withValues(alpha: .06 + .07 * _frac(i * .37));
      canvas.drawLine(Offset(x, y), Offset(x - 3, y + 14), rain);
    }
    for (var i = 0; i < 12; i++) {
      final x = _frac(i * .413 + math.sin(a * math.pi * 2 + i) * .02) * w;
      final y = _frac(i * .271 - a) * h;
      canvas.drawCircle(Offset(x, y), 1.5,
          Paint()..color = shineGold.withValues(alpha: .24));
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.accent != accent;
}

class _FloorPainter extends CustomPainter {
  const _FloorPainter(this.centers, this.cw, this.ch, this.accents);
  final List<Offset> centers;
  final double cw, ch;
  final List<Color> accents;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < centers.length; i++) {
      final c = centers[i];
      final rect = Rect.fromCenter(center: Offset(c.dx, c.dy + ch * .5 + 2),
          width: cw * 1.28, height: ch * .12);
      canvas.drawOval(rect.inflate(10), Paint()
        ..color = accents[i].withValues(alpha: .26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      canvas.drawOval(rect, Paint()
        ..color = Colors.black.withValues(alpha: .65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    }
  }
  @override
  bool shouldRepaint(covariant _FloorPainter old) => true;
}

// ───────────── Efek di atas panggung ─────────────

Path _hexPath(Offset c, double rx, double ry, {bool flat = false}) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = (flat ? 0 : -math.pi / 2) + i * math.pi / 3;
    final pt = Offset(c.dx + rx * math.cos(a), c.dy + ry * math.sin(a));
    if (i == 0) { p.moveTo(pt.dx, pt.dy); } else { p.lineTo(pt.dx, pt.dy); }
  }
  return p..close();
}

class _StagePainter extends CustomPainter {
  _StagePainter({required this.ambA, required this.fxA, required this.fx,
    required this.leftSide, required this.centers, required this.cw,
    required this.ch, required this.shieldAmt, required this.shieldAlpha,
    required this.reserves, required this.reserveAlpha, required this.aim,
    required this.aimSide, required this.skillAura, required this.auraSide})
      : super(repaint: Listenable.merge([ambA, fxA]));
  final Animation<double> ambA;
  final AnimationController fxA;
  final _Fx? fx;
  final int leftSide;
  final List<Offset> centers;
  final double cw, ch;
  final List<double> shieldAmt, shieldAlpha, reserveAlpha;
  final List<int> reserves;
  final double aim;
  final int aimSide, auraSide;
  final bool skillAura;

  Offset pos(int side) => side == leftSide ? centers[0] : centers[1];

  void _glowLine(Canvas c, Offset a, Offset b, Color color, double w, double alpha) {
    c.drawLine(a, b, Paint()..color = color.withValues(alpha: alpha * .75)
      ..strokeWidth = w * 2.4..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawLine(a, b, Paint()..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = w * .55..strokeCap = StrokeCap.round);
  }

  void _ring(Canvas c, Offset ctr, double r, Color color, double w, double alpha) {
    if (alpha <= 0) return;
    c.drawCircle(ctr, r, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 2
      ..color = color.withValues(alpha: alpha * .6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    c.drawCircle(ctr, r, Paint()..style = PaintingStyle.stroke..strokeWidth = w
      ..color = Color.lerp(color, Colors.white, .6)!.withValues(alpha: alpha));
  }

  void _dot(Canvas c, Offset p, double r, Color color, double alpha) {
    c.drawCircle(p, r * 2.2, Paint()..color = color.withValues(alpha: alpha * .6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(p, r, Paint()..color = Color.lerp(color, Colors.white, .7)!
        .withValues(alpha: alpha));
  }

  void _shield(Canvas canvas, Offset c, double alpha, double amt, double amb,
      {double scale = 1, bool badge = true}) {
    if (alpha <= 0) return;
    final rx = cw * .78 * scale, ry = ch * .6 * scale;
    final path = _hexPath(c, rx, ry);
    final a = (alpha * (.78 + .22 * math.sin(amb * math.pi * 6))).clamp(0.0, 1.0);
    canvas.drawPath(path, Paint()..shader = RadialGradient(colors: [
      Colors.transparent, shineAzure.withValues(alpha: .26 * a)])
        .createShader(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2)));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 6
      ..color = shineAzure.withValues(alpha: .7 * a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2
      ..color = Colors.white.withValues(alpha: .85 * a));
    canvas.drawPath(_hexPath(c, rx * .88, ry * .88), Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1
      ..color = shineAzure.withValues(alpha: .45 * a));
    if (badge && amt > 0) {
      final bc = Offset(c.dx + rx * .866, c.dy - ry * .5);
      canvas.drawCircle(bc, 14, Paint()..color = const Color(0xFF0E2A44).withValues(alpha: a));
      canvas.drawCircle(bc, 14, Paint()..style = PaintingStyle.stroke..strokeWidth = 2
        ..color = shineAzure.withValues(alpha: a));
      final tp = TextPainter(text: TextSpan(text: '${amt.toInt()}',
          style: TextStyle(color: Colors.white.withValues(alpha: a),
              fontWeight: FontWeight.w900, fontSize: 14)),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, bc - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _orbs(Canvas canvas, Offset c, int n, double alpha, double amb) {
    for (var i = 0; i < n; i++) {
      final a = amb * math.pi * 2 + i * math.pi * 2 / n;
      final p = Offset(c.dx + math.cos(a) * cw * .62,
          c.dy + ch * .2 + math.sin(a) * ch * .1);
      _dot(canvas, p, 5.5 + 1.8 * math.sin(a), shineGold, alpha);
    }
  }

  void _reticle(Canvas canvas, Offset c, double amb) {
    final r = ch * (.38 + .06 * aim) + math.sin(amb * math.pi * 6) * 3;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8
      ..color = shineEmber.withValues(alpha: .1 + .16 * aim)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
          amb * math.pi * 2 + i * math.pi / 2, math.pi / 3, false,
          Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
            ..strokeWidth = 2.5 + 2 * aim..color = shineEmber.withValues(alpha: .9));
      final d = Offset(math.cos(i * math.pi / 2), math.sin(i * math.pi / 2));
      canvas.drawLine(c + d * (r + 5), c + d * (r + 15), Paint()
        ..strokeWidth = 2.5..color = shineEmber.withValues(alpha: .85));
    }
    canvas.drawCircle(c, 3, Paint()..color = shineEmber);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final amb = ambA.value;
    for (var side = 0; side < 2; side++) {
      final c = pos(side);
      _shield(canvas, c, shieldAlpha[side], shieldAmt[side], amb);
      if (reserves[side] > 0) _orbs(canvas, c, reserves[side], reserveAlpha[side], amb);
    }
    if (skillAura) {
      final c = pos(auraSide);
      final r = ch * .55 + math.sin(amb * math.pi * 6) * 4;
      canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [
        Colors.transparent, shineViolet.withValues(alpha: .3)])
          .createShader(Rect.fromCircle(center: c, radius: r)));
      _ring(canvas, c, r, shineViolet, 2.5, .8);
    }
    if (aim > 0) _reticle(canvas, pos(aimSide), amb);

    final e = fx;
    if (e == null || !fxA.isAnimating) return;
    final t = fxA.value;
    final ac = pos(e.actor), tc = pos(e.target);

    if (e.attacked && t >= .2) {
      const ta = .22;
      if (e.damage > 0) {
        final n = 1 + (e.attackPts >= 3 ? 1 : 0) + (e.attackPts >= 6 ? 1 : 0);
        for (var i = 0; i < n; i++) {
          final k = (i - (n - 1) / 2) * cw * .3;
          final p0 = Offset(tc.dx + cw * .45 + k, tc.dy - ch * .45);
          final p1 = Offset(tc.dx - cw * .45 + k, tc.dy + ch * .45);
          final s = Curves.easeOut.transform(_seg(t, ta + i * .05, ta + .2 + i * .05));
          final fade = 1 - _seg(t, ta + .3, ta + .6);
          if (s > 0) _glowLine(canvas, p0, Offset.lerp(p0, p1, s)!, shineEmber,
              5 + 4 * e.intensity, fade);
        }
        final rp = _seg(t, ta, ta + .4);
        _ring(canvas, tc, 10 + (ch * .7) * Curves.easeOut.transform(rp),
            shineEmber, 4, (1 - rp));
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi * 2 / 10 + .3;
          final d = Offset(math.cos(a), math.sin(a));
          final r0 = ch * .18 + rp * ch * .2, r1 = r0 + ch * .12 * (1 - rp);
          _glowLine(canvas, tc + d * r0, tc + d * r1, shineGold, 2.5, 1 - rp);
        }
      } else {
        final rp = _seg(t, ta, ta + .4);
        _ring(canvas, tc, ch * .3 + ch * .25 * rp, shineAzure, 4, 1 - rp);
      }
      if (e.absorbed > 0) {
        final p = _seg(t, ta, ta + .35);
        _shield(canvas, tc, (1 - p) * .95, 0, amb,
            scale: 1 + .5 * Curves.easeOut.transform(p), badge: false);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + .2;
          final d = Offset(math.cos(a), math.sin(a) * 1.3);
          final from = tc + Offset(d.dx * cw * .55, d.dy * ch * .4);
          _glowLine(canvas, from, from + d * (18 + 40 * p), shineAzure, 3, (1 - p));
        }
      }
    }

    if (e.defend > 0) {
      final p = _seg(t, 0, .5);
      _shield(canvas, ac, (1 - p) * .9, 0, amb,
          scale: .5 + .65 * Curves.easeOut.transform(p), badge: false);
      final g = Rect.fromCenter(center: Offset(ac.dx, ac.dy + ch * .5),
          width: cw * (.8 + p), height: ch * .1 * (.6 + p));
      canvas.drawOval(g, Paint()..style = PaintingStyle.stroke..strokeWidth = 3
        ..color = shineAzure.withValues(alpha: 1 - p));
    }

    if (e.reserveSaved > 0) {
      final n = math.min(10, e.reserveSaved * 2 + 2);
      for (var i = 0; i < n; i++) {
        final p = _seg(t, i * .03, .72 + i * .03);
        if (p <= 0 || p >= 1) continue;
        final x = ac.dx + math.sin(i * 2.4) * cw * .5 * (1 - p * .6);
        final y = ac.dy + ch * .45 - (ch * .27) * Curves.easeOut.transform(p);
        _dot(canvas, Offset(x, y), 4, shineGold, math.sin(p * math.pi));
      }
      final gp = _seg(t, 0, .5);
      canvas.drawOval(Rect.fromCenter(center: Offset(ac.dx, ac.dy + ch * .5),
          width: cw * (.6 + gp), height: ch * .09 * (.6 + gp)),
          Paint()..style = PaintingStyle.stroke..strokeWidth = 3
            ..color = shineGold.withValues(alpha: 1 - gp));
    }

    if (e.skill) {
      final p = _seg(t, 0, .5);
      final r = 10 + ch * .75 * Curves.easeOut.transform(p);
      canvas.drawCircle(ac, ch * .5, Paint()..shader = RadialGradient(colors: [
        shineViolet.withValues(alpha: (1 - p) * .5), Colors.transparent])
          .createShader(Rect.fromCircle(center: ac, radius: ch * .5)));
      _ring(canvas, ac, r, shineViolet, 5 * (1 - p) + 1, 1 - p);
      for (var i = 0; i < 14; i++) {
        final a = i * math.pi * 2 / 14;
        final d = Offset(math.cos(a), math.sin(a));
        _glowLine(canvas, ac + d * r * .55, ac + d * r * .95, shineViolet, 2.2, 1 - p);
      }
    }

    if (e.passive) {
      final p = _seg(t, 0, .85);
      final a = math.sin(p * math.pi);
      for (var i = 0; i < 3; i++) {
        canvas.drawArc(Rect.fromCenter(center: ac, width: cw * (1.15 + .18 * i),
            height: ch * (.8 + .1 * i)), t * math.pi * 3 + i * 2.1, math.pi / 2.3, false,
            Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
              ..strokeWidth = 3..color = const Color(0xFFCFE6FF).withValues(alpha: a * .7));
      }
      for (var i = 0; i < 4; i++) {
        final q = _seg(t, i * .06, .6 + i * .06);
        final side = i.isEven ? -1.0 : 1.0;
        canvas.drawOval(Rect.fromCenter(
            center: Offset(ac.dx + side * cw * (.2 + .25 * q), ac.dy + ch * .5),
            width: 20 + 30 * q, height: 7 + 8 * q),
            Paint()..color = Colors.white.withValues(alpha: .25 * (1 - q)));
      }
    }

    if (e.timeout) {
      final p = _seg(t, 0, .6);
      final r = ch * .2 + ch * .5 * Curves.easeOut.transform(p);
      _ring(canvas, ac, r, shineMuted, 4, 1 - p);
    }

    if (e.heal > 0) {
      for (var i = 0; i < 9; i++) {
        final p = _seg(t, .08 + i * .05, .7 + i * .05);
        if (p <= 0 || p >= 1) continue;
        final x = ac.dx + math.sin(i * 2.1) * cw * .42;
        final y = ac.dy + ch * .3 - ch * .8 * Curves.easeOut.transform(p);
        final a = math.sin(p * math.pi);
        final pa = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round
          ..color = shineJade.withValues(alpha: a);
        canvas.drawLine(Offset(x - 7, y), Offset(x + 7, y), pa);
        canvas.drawLine(Offset(x, y - 7), Offset(x, y + 7), pa);
      }
    }

    for (final g in e.ghosts) {
      final gc = pos(g.side);
      if (g.ko) {
        final p = _seg(t, .3, .85);
        if (p > 0) {
          _ring(canvas, gc, 10 + ch * .6 * Curves.easeOut.transform(p), shineEmber, 4, 1 - p);
        }
      } else {
        final p = _seg(t, .4, .75);
        _ring(canvas, gc, ch * .2 + ch * .45 * p, shineGold, 4, 1 - p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}

// ───────────── Kartu di panggung & Open Broadcast HUD ─────────────

class _CardFace extends StatelessWidget {
  const _CardFace({required this.spec, required this.accent, this.tint,
    this.tintAlpha = 0, this.gray = false});
  final CharacterSpec spec;
  final Color accent;
  final Color? tint;
  final double tintAlpha;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    final face = Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: .42), blurRadius: 28, spreadRadius: -4),
            BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 16, offset: const Offset(0, 10)),
          ]),
      child: Stack(fit: StackFit.expand, children: [
        Portrait(spec, radius: 18, borderColor: accent),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                stops: const [.6, 1], colors: [Colors.transparent, Colors.black.withValues(alpha: .9)])))),
        Positioned(left: 8, right: 8, bottom: 9, child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center, style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: .5)),
          Text(spec.skill, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: shineGold, fontWeight: FontWeight.w700)),
        ])),
        if (tint != null && tintAlpha > 0) Positioned.fill(child: IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: tint!.withValues(alpha: tintAlpha.clamp(0.0, 1.0)))))),
      ]),
    );
    if (!gray) return face;
    return ColorFiltered(colorFilter: const ColorFilter.matrix(<double>[
      .2126, .7152, .0722, 0, 0, .2126, .7152, .0722, 0, 0,
      .2126, .7152, .0722, 0, 0, 0, 0, 0, 1, 0]), child: face);
  }
}

/// HUD terbuka tanpa kotak tebal ("broadcast fighter overlay").
class _FighterBroadcastHud extends StatelessWidget {
  const _FighterBroadcastHud({
    required this.team, required this.mirrored,
    required this.accent, required this.label, required this.isTurn,
    this.big = false,
  });
  final Map<String, dynamic> team;
  final bool mirrored, isTurn, big;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cards = team['cards'] as List;
    final unit = Map<String, dynamic>.from(cards[(team['active'] as num).toInt()] as Map);
    final spec = characterById(unit['id'] as String);
    final hp = (unit['hp'] as num).toInt();
    final maxHp = (unit['max_hp'] as num?)?.toInt() ?? spec.hp;
    final reserve = (team['reserve'] as num).toInt();
    final block = (team['block'] as num).toInt();
    final align = mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlign = mirrored ? MainAxisAlignment.end : MainAxisAlignment.start;

    final avatar = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: isTurn
            ? [BoxShadow(color: accent.withValues(alpha: .55), blurRadius: 16, spreadRadius: -2)]
            : null,
      ),
      child: Portrait(
        spec,
        width: big ? 58 : 46,
        height: big ? 76 : 62,
        radius: 11,
        borderColor: isTurn ? accent : Colors.white24,
      ),
    );

    final stats = Expanded(
      child: Column(
        crossAxisAlignment: align,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: rowAlign,
            children: [
              if (!mirrored && isTurn)
                Container(
                  width: 6, height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: accent, blurRadius: 6)]),
                ),
              Text(label, style: TextStyle(
                  color: accent, fontSize: 9.5,
                  fontWeight: FontWeight.w900, letterSpacing: 1.8)),
              if (mirrored && isTurn)
                Container(
                  width: 6, height: 6,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: accent, blurRadius: 6)]),
                ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisAlignment: rowAlign,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (!mirrored) ...[
                Flexible(
                  child: Text(spec.name.toUpperCase(), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: big ? 15 : 12.5,
                          fontWeight: FontWeight.w900, letterSpacing: .5)),
                ),
                const SizedBox(width: 8),
                Text('$hp', style: TextStyle(
                    fontSize: big ? 20 : 16, fontWeight: FontWeight.w900,
                    color: shineJade)),
                Text('/$maxHp', style: const TextStyle(fontSize: 10, color: shineMuted)),
              ] else ...[
                Text('$hp', style: TextStyle(
                    fontSize: big ? 20 : 16, fontWeight: FontWeight.w900,
                    color: shineJade)),
                Text('/$maxHp', style: const TextStyle(fontSize: 10, color: shineMuted)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(spec.name.toUpperCase(), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: big ? 15 : 12.5,
                          fontWeight: FontWeight.w900, letterSpacing: .5)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          HpBar(hp: hp, maxHp: maxHp, height: big ? 9 : 7.5,
              showText: false, mirrored: mirrored),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: rowAlign,
            children: [
              _miniStat(Icons.flash_on_rounded, '${spec.attack}', shineEmber),
              const SizedBox(width: 10),
              _miniStat(Icons.bolt_rounded, '$reserve PA', shineGold),
              const SizedBox(width: 10),
              _miniStat(Icons.shield_rounded, '$block', shineAzure),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: mirrored
            ? [stats, const SizedBox(width: 10), avatar]
            : [avatar, const SizedBox(width: 10), stats],
      ),
    );
  }

  Widget _miniStat(IconData icon, String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 2),
      Text(text, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w900, color: color)),
    ],
  );
}

class _HexPainter extends CustomPainter {
  const _HexPainter(this.color, this.active, this.enabled);
  final Color color;
  final bool active, enabled;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = enabled ? color : const Color(0xFF4A465C);
    final path = _hexPath(c, size.width / 2 - 2, size.height / 2 - 2, flat: true);
    if (active && enabled) {
      canvas.drawPath(path, Paint()..color = base.withValues(alpha: .7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    }
    canvas.drawPath(path, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color.lerp(base, Colors.white, .32)!, base,
          Color.lerp(base, Colors.black, .48)!]).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2
      ..color = Colors.white.withValues(alpha: enabled ? .88 : .28));
    canvas.drawPath(_hexPath(c, size.width / 2 - 8, size.height / 2 - 7, flat: true),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1
          ..color = Colors.white.withValues(alpha: enabled ? .42 : .15));
  }
  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.color != color || old.active != active || old.enabled != enabled;
}

class _HexButton extends StatelessWidget {
  const _HexButton({required this.icon, required this.color, required this.label,
    required this.count, required this.onTap, this.onMinus, this.onLongPress,
    this.enabled = true, this.cooldown = 0, this.badgeText, this.scale = 1});
  final IconData icon;
  final Color color;
  final String label;
  final int count, cooldown;
  final String? badgeText;
  final VoidCallback? onTap, onMinus, onLongPress;
  final bool enabled;
  final double scale;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 74 * scale, height: 64 * scale, child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null, onLongPress: enabled ? onLongPress : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: count > 0 && enabled ? 1.06 : 1,
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _HexPainter(color, count > 0, enabled))),
            Center(child: cooldown > 0
                ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_bottom, color: Colors.white70, size: 18),
              Text('$cooldown', style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 14)),
            ])
                : Icon(icon, color: Colors.white, size: 29 * scale,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)])),
            Positioned(right: 0, bottom: 0, child: Container(
                constraints: const BoxConstraints(minWidth: 25),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: const Color(0xFF0E0C17),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: enabled ? color : Colors.white24, width: 1.4)),
                child: Text(badgeText ?? '$count', textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w900, fontSize: 12)))),
            if (onMinus != null && count > 0 && enabled) Positioned(left: 0, top: 0,
                child: GestureDetector(onTap: onMinus, child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(color: const Color(0xFF0E0C17), shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70)),
                    child: const Icon(Icons.remove, size: 14, color: Colors.white)))),
          ]),
        ),
      ),
    )),
    const SizedBox(height: 4),
    SizedBox(width: 80 * scale, child: Text(label, maxLines: 1,
        textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 9.5, height: 1.1,
            fontWeight: FontWeight.w900, letterSpacing: .6,
            color: enabled ? Color.lerp(color, Colors.white, .38) : Colors.white30))),
  ]);
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

class _MatchArenaState extends State<MatchArena> with TickerProviderStateMixin {
  int attack = 0, defend = 0, reserve = 0;
  bool skill = false, busy = false;
  Timer? _countdown, _bannerTimer, _resultTimer;
  bool _timeoutNotified = false;
  DateTime? _lastTimeoutAttempt;
  int _turnTotal = 30;
  bool _resultReady = false;
  _Fx? _event;
  bool _wide = false;
  bool _short = false;
  late final AnimationController _fxC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1850));
  late final AnimationController _amb = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000));
  late final AnimationController _bannerC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700));

  int get remainingSeconds => widget.turnDeadline == null ? 0 : math.max(0,
      (widget.turnDeadline!.difference(DateTime.now().toUtc()).inMilliseconds / 1000).ceil());
  int get turn => (widget.state['turn'] as num).toInt();
  int get activeSide => (turn-1)%2;
  List<dynamic> get teams => widget.state['teams'] as List<dynamic>;
  Map<String,dynamic> _team(int side) => Map<String,dynamic>.from(teams[side] as Map);
  // Gunakan tim viewer sendiri saat tidak sedang aktif agar tombol komando tidak berkedip ganti nama skill lawan
  int get _commandSide => _personal ? widget.viewerSide : activeSide;
  Map<String,dynamic> get own => _team(_commandSide);
  Map<String,dynamic> get ownCard => Map<String,dynamic>.from((own['cards'] as List)[(own['active'] as num).toInt()] as Map);
  CharacterSpec get spec => characterById(ownCard['id'] as String);
  int get available => math.min(8, math.min(turn,4)+(own['reserve'] as num).toInt());
  int get spent => attack+defend+reserve+(skill ? spec.cost : 0);
  int get foeBlock => (_team(1-_commandSide)['block'] as num).toInt();
  bool get _offensive => const {'damage','pierce','recoil','conditional_damage','hybrid'}.contains(spec.kind);
  bool get _personal => widget.isBotMatch || widget.onReplay == null;
  int get _left => _personal ? widget.viewerSide : 0;
  int get _right => 1 - _left;
  bool get _planning => widget.canAct && widget.state['winner'] == null;

  void reset() {
    skill=false; defend=0;
    reserve=math.min(4,math.max(0,available-1));
    attack=available-reserve;
  }

  @override
  void initState() {
    super.initState();
    reset();
    _amb.repeat();
    _resultReady = widget.state['winner'] != null;
    _turnTotal = math.max(1, remainingSeconds);
    _playBanner();
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
    _countdown?.cancel(); _bannerTimer?.cancel(); _resultTimer?.cancel();
    _fxC.dispose(); _amb.dispose(); _bannerC.dispose();
    super.dispose();
  }

  void _playBanner({int delayMs = 0}) {
    _bannerTimer?.cancel();
    _bannerTimer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted && widget.state['winner'] == null) _bannerC.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant MatchArena oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state['turn'] != widget.state['turn']) {
      reset();
      final fx = _buildFx(oldWidget.state, widget.state);
      if (fx != null) {
        _event = fx;
        _fxC.forward(from: 0);
        if (fx.attacked) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }
      _playBanner(delayMs: fx == null ? 0 : 1450);
    }
    if (oldWidget.state['winner'] == null && widget.state['winner'] != null) {
      _resultTimer?.cancel();
      _resultTimer = Timer(const Duration(milliseconds: 1750), () {
        if (mounted) setState(() => _resultReady = true);
      });
    }
    if (oldWidget.turnDeadline != widget.turnDeadline ||
        oldWidget.state['turn'] != widget.state['turn']) {
      _timeoutNotified = false;
      _lastTimeoutAttempt = null;
      _turnTotal = math.max(1, remainingSeconds);
    }
  }

  _Fx? _buildFx(Map<String,dynamic> oldS, Map<String,dynamic> newS) {
    try {
      final oldTurn = (oldS['turn'] as num).toInt();
      final newTurn = (newS['turn'] as num).toInt();
      if (newTurn <= oldTurn) return null;
      final actor = (oldTurn - 1) % 2;
      final log = newS['log'] as String? ?? '';
      Map<String,dynamic> tm(Map<String,dynamic> s, int i) =>
          Map<String,dynamic>.from((s['teams'] as List)[i] as Map);
      final oa = tm(oldS, actor), na = tm(newS, actor);
      final ot = tm(oldS, 1 - actor), nt = tm(newS, 1 - actor);
      int hp(Map<String,dynamic> t, int i) =>
          (((t['cards'] as List)[i] as Map)['hp'] as num).toInt();
      int act(Map<String,dynamic> t) => (t['active'] as num).toInt();
      String idAt(Map<String,dynamic> t, int i) =>
          ((t['cards'] as List)[i] as Map)['id'] as String;
      final swap = log.contains('mengganti') || log.contains('berganti');
      final timeout = log.contains('Waktu');
      final m = RegExp(r'(\d+) serang, (\d+) bertahan, (\d+) cadangan').firstMatch(log);
      final sk = RegExp(r'Skill (.+?) aktif').firstMatch(log);
      final tIdx = act(ot), aIdx = act(oa);
      var heal = 0;
      for (var i = 0; i < 3; i++) {
        final d = hp(na, i) - hp(oa, i);
        if (d > 0) heal += d;
      }
      final ghosts = <_Ghost>[];
      if (hp(ot, tIdx) > 0 && hp(nt, tIdx) <= 0) {
        ghosts.add(_Ghost(1 - actor, idAt(ot, tIdx), true));
      }
      if (hp(oa, aIdx) > 0 && hp(na, aIdx) <= 0) {
        ghosts.add(_Ghost(actor, idAt(oa, aIdx), true));
      } else if (swap && act(na) != aIdx) {
        ghosts.add(_Ghost(actor, idAt(oa, aIdx), false));
      }
      final pts = m == null ? 0 : int.parse(m.group(1)!);
      return _Fx(
          actor: actor, attackPts: pts,
          defend: m == null ? 0 : int.parse(m.group(2)!),
          reserveSaved: m == null ? 0 : int.parse(m.group(3)!),
          damage: math.max(0, hp(ot, tIdx) - hp(nt, tIdx)),
          absorbed: math.min(pts, (ot['block'] as num).toInt()),
          oldBlockTarget: (ot['block'] as num).toInt(),
          skill: sk != null, skillName: sk?.group(1) ?? '',
          swap: swap, timeout: timeout, heal: heal,
          selfDamage: math.max(0, hp(oa, aIdx) - hp(na, aIdx)),
          ghosts: ghosts);
    } catch (_) { return null; }
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

  void _add(String what, {bool fill = false}) {
    final free = available - spent;
    if (free <= 0) { HapticFeedback.heavyImpact(); return; }
    setState(() {
      final room = what == 'a' ? 8 - attack : what == 'd' ? 8 - defend : 4 - reserve;
      final n = math.min(room, fill ? free : 1);
      if (n <= 0) return;
      if (what == 'a') { attack += n; }
      else if (what == 'd') { defend += n; }
      else { reserve += n; }
    });
    HapticFeedback.selectionClick();
  }

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

  String _sideLabel(int side) {
    if (widget.isBotMatch) return side == widget.viewerSide ? 'KAMU' : 'KOMPUTER';
    if (!_personal) return 'TIM ${side == 0 ? 'A' : 'B'}';
    return side == widget.viewerSide ? 'KAMU' : 'LAWAN';
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

  void _showMenu() => showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        Widget tile(IconData icon, String text, VoidCallback run, {Color? color}) =>
            ListTile(leading: Icon(icon, color: color ?? shineGold),
                title: Text(text, style: TextStyle(color: color)),
                onTap: () { Navigator.pop(sheet); run(); });
        return SafeArea(child: Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.title, style: const TextStyle(color: shineGold,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 6),
              if (widget.onExit != null)
                tile(Icons.home_outlined, 'Beranda (pertandingan tetap ada)', widget.onExit!),
              if (widget.history.isNotEmpty)
                tile(Icons.history, 'Riwayat pertarungan', _showHistory),
              if (widget.onSurrender != null)
                tile(Icons.flag_outlined, 'Menyerah (lawan menang)',
                        () => widget.onSurrender!(), color: shineEmber),
              if (widget.onDisband != null)
                tile(Icons.delete_outline, 'Bubarkan ruang (host)',
                        () => widget.onDisband!(), color: shineEmber),
              if (widget.onStopLocal != null)
                tile(Icons.stop_circle_outlined, 'Hentikan pertandingan lokal',
                        () => widget.onStopLocal!(), color: shineEmber),
            ])));
      });

  // ───────────── Pose kartu ─────────────

  _Pose _poseFor(int side, double t, _Fx? fx, double gap) {
    final toward = side == _left ? 1.0 : -1.0;
    if (fx == null) {
      if (_planning && side == activeSide && !busy) {
        if (attack > 0) {
          return _Pose(dx: toward * (4 + 2.0 * math.min(attack, 6)), scale: 1.015);
        }
        return _Pose(dx: -toward * 8, scale: .96);
      }
      return const _Pose();
    }
    var dx = 0.0, dy = 0.0, sc = 1.0, rot = 0.0, flash = 0.0, op = 1.0;
    var fc = shineEmber;
    if (side == fx.actor) {
      if (fx.attacked) {
        final out = Curves.easeOutCubic.transform(_seg(t, 0, .22));
        final back = Curves.easeInOut.transform(_seg(t, .32, .62));
        final d = out * (1 - back);
        dx = toward * gap * .62 * d; rot = toward * .06 * d; sc = 1 + .08 * d;
      } else if (fx.timeout) {
        sc = 1 - .04 * math.sin(math.pi * _seg(t, 0, .6));
      } else if (!fx.swap) {
        final p = math.sin(math.pi * _seg(t, 0, .7));
        sc = 1 - .07 * p; dx = -toward * 14 * p; dy = 6 * p;
      }
      if (fx.defend > 0) sc *= 1 + .05 * math.sin(math.pi * _seg(t, 0, .5));
      if (fx.heal > 0) {
        flash = .35 * math.sin(math.pi * _seg(t, .1, .8)); fc = shineJade;
      }
      if (fx.selfDamage > 0) {
        final p = _seg(t, .25, .7);
        if (p > 0) {
          flash = math.max(flash, .5 * (1 - p)); fc = shineEmber;
          dx += math.sin(p * math.pi * 8) * 6 * (1 - p);
        }
      }
    } else if (fx.attacked) {
      final p = _seg(t, .22, .75);
      if (p > 0 && p < 1) {
        final amp = (fx.damage > 0 ? 9.0 : 3.0) * (.4 + fx.intensity) * (1 - p);
        final actorDir = fx.actor == _left ? 1.0 : -1.0;
        dx = math.sin(p * math.pi * 9) * amp +
            actorDir * 16 * fx.intensity * math.sin(math.pi * _seg(t, .22, .5));
        if (fx.damage > 0) {
          flash = .55 * (1 - _seg(t, .22, .5)); fc = shineEmber;
        } else {
          flash = .3 * (1 - _seg(t, .22, .45)); fc = shineAzure;
        }
      }
    }
    for (final g in fx.ghosts) {
      if (g.side != side) continue;
      final st = g.ko ? .62 : .42;
      final e = Curves.easeOutCubic.transform(_seg(t, st, st + .3));
      op = e; dx += (side == _left ? -1 : 1) * 70 * (1 - e);
    }
    return _Pose(dx: dx, dy: dy, scale: sc, rot: rot, flash: flash,
        flashColor: fc, opacity: op);
  }

  Widget _slot(int side, Offset c, double cw, double ch, _Pose pose,
      _Fx? fx, double t) {
    final team = _team(side);
    final unit = Map<String,dynamic>.from(
        (team['cards'] as List)[(team['active'] as num).toInt()] as Map);
    final cur = characterById(unit['id'] as String);
    final accent = side == _left ? shineAzure : shineEmber;
    final out = side == _left ? -1.0 : 1.0;
    _Ghost? ghost;
    if (fx != null) {
      for (final g in fx.ghosts) { if (g.side == side) ghost = g; }
    }
    final kids = <Widget>[];
    if (ghost != null) {
      final g = ghost;
      final p = g.ko ? _seg(t, .3, .78) : _seg(t, 0, .45);
      kids.add(Positioned.fill(child: Opacity(
          opacity: (1 - p).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: g.ko ? Offset(out * 20 * p, 50 * p) : Offset(out * 90 * p, 0),
            child: Transform.rotate(angle: g.ko ? out * .5 * p : 0,
                child: Stack(fit: StackFit.expand, children: [
                  _CardFace(spec: characterById(g.id), accent: accent,
                      gray: g.ko && p > 0, tint: shineEmber,
                      tintAlpha: g.ko ? .4 * _seg(t, .22, .4) : 0),
                  if (g.ko && p > 0) Center(child: Transform.rotate(angle: -.25,
                      child: Text('KO', style: TextStyle(fontSize: 54,
                          fontWeight: FontWeight.w900, letterSpacing: 4,
                          color: shineEmber.withValues(alpha: _seg(t, .3, .42)),
                          shadows: const [Shadow(color: Colors.black, blurRadius: 10)])))),
                ])),
          ))));
    }
    kids.add(Positioned.fill(child: Opacity(opacity: pose.opacity.clamp(0.0, 1.0),
        child: _CardFace(spec: cur, accent: accent,
            tint: pose.flashColor, tintAlpha: pose.flash))));
    return Positioned(
      left: c.dx - cw / 2 + pose.dx, top: c.dy - ch / 2 + pose.dy,
      width: cw, height: ch,
      child: Transform.rotate(angle: pose.rot + (side == _left ? .02 : -.02),
          child: Transform.scale(scale: pose.scale,
              child: AnimatedBuilder(animation: _amb,
                  child: Stack(clipBehavior: Clip.none, children: kids),
                  builder: (context, child) => Transform.translate(
                      offset: Offset(0, 3 * math.sin(_amb.value * math.pi * 2 + side)),
                      child: child)))),
    );
  }

  Widget _bench(int side, bool left) {
    final team = _team(side);
    final cards = team['cards'] as List;
    final active = (team['active'] as num).toInt();
    final tappable = _planning && !busy && side == activeSide;
    return Positioned(top: 10, left: left ? 8 : null, right: left ? null : 8,
        child: Column(children: [
          for (var i = 0; i < 3; i++) if (i != active) Builder(builder: (context) {
            final f = Map<String,dynamic>.from(cards[i] as Map);
            final sp = characterById(f['id'] as String);
            final hp = (f['hp'] as num).toInt();
            final alive = hp > 0;
            final maxHp = (f['max_hp'] as num?)?.toInt() ?? sp.hp;
            return Padding(padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: tappable && alive ? () => _confirmSwap(i) : null,
                  child: Opacity(opacity: alive ? 1 : .35, child: Container(
                    width: _wide ? 58 : 46, height: _wide ? 80 : 64,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                        boxShadow: tappable && alive
                            ? [BoxShadow(color: shineGold.withValues(alpha: .45), blurRadius: 10)]
                            : null),
                    child: Stack(fit: StackFit.expand, children: [
                      Portrait(sp, radius: 10),
                      Positioned(left: 4, right: 4, bottom: 4, child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                              value: maxHp == 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0),
                              minHeight: 3.5, backgroundColor: Colors.black54,
                              color: hp / maxHp > .3 ? shineJade : shineEmber))),
                      if (!alive) const Center(child: Text('KO', style: TextStyle(
                          color: shineEmber, fontWeight: FontWeight.w900, fontSize: 14))),
                      if (tappable && alive) Positioned(top: 2, right: 2, child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: shineGold, shape: BoxShape.circle),
                          child: const Icon(Icons.swap_horiz, size: 10, color: Colors.black))),
                    ]),
                  )),
                ));
          }),
        ]));
  }

  // ───────────── Teks mengambang & banner ─────────────

  Widget _float(double t, Offset at, String text, Color color, double size,
      double a, double b, double rise) {
    final p = _seg(t, a, b);
    if (p <= 0 || p >= 1) return const SizedBox.shrink();
    final op = p < .15 ? p / .15 : 1 - _seg(p, .65, 1);
    final sc = .6 + .4 * Curves.easeOutBack.transform(_seg(p, 0, .25));
    return Positioned(left: at.dx - 140, top: at.dy - rise * Curves.easeOut.transform(p) - size,
        width: 280, child: IgnorePointer(child: Opacity(opacity: op.clamp(0.0, 1.0),
            child: Transform.scale(scale: sc, child: Center(child: Text(text,
                textAlign: TextAlign.center, style: TextStyle(fontSize: size,
                    fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                    letterSpacing: 1.5, color: color, shadows: [
                      const Shadow(color: Colors.black, blurRadius: 6),
                      Shadow(color: color.withValues(alpha: .8), blurRadius: 18)])))))));
  }

  List<Widget> _floats(double t, _Fx e, Offset Function(int) cen, double ch) {
    final ac = cen(e.actor), tc = cen(e.target);
    final w = <Widget>[];
    if (e.attacked) {
      if (e.damage > 0) {
        w.add(_float(t, tc.translate(0, -ch * .1), '-${e.damage}', Colors.white,
            26 + 22 * e.intensity, .24, 1, ch * .35));
        if (e.absorbed > 0) {
          w.add(_float(t, tc.translate(0, ch * .22), 'TAMENG -${e.absorbed}',
              shineAzure, 15, .3, .95, ch * .12));
        }
      } else {
        w.add(_float(t, tc.translate(0, -ch * .05), 'TERTAHAN!', shineAzure, 26, .24, .95, ch * .25));
      }
      if (e.defend > 0) w.add(_float(t, ac.translate(0, ch * .3), 'TAMENG ×${e.defend}', shineAzure, 14, .1, .85, ch * .15));
      if (e.reserveSaved > 0) w.add(_float(t, ac.translate(0, ch * .42), 'PA +${e.reserveSaved}', shineGold, 14, .3, .95, ch * .12));
    } else if (e.passive) {
      final label = e.defend > 0 && e.reserveSaved > 0 ? 'BERTAHAN & SIAGA'
          : e.defend > 0 ? 'BERTAHAN!' : e.reserveSaved > 0 ? 'MENGUMPULKAN PA' : 'BERSIAGA';
      w.add(_float(t, ac.translate(0, -ch * .15), label,
          e.defend > 0 ? shineAzure : (e.reserveSaved > 0 ? shineGold : Colors.white),
          22, .05, .95, ch * .3));
    } else if (e.timeout) {
      w.add(_float(t, ac, 'WAKTU HABIS', shineMuted, 24, .05, .95, ch * .25));
    } else if (e.swap) {
      w.add(_float(t, ac, 'GANTI TOKOH', shineGold, 24, .4, 1, ch * .25));
    }
    if (e.heal > 0) w.add(_float(t, ac.translate(0, -ch * .2), '+${e.heal}', shineJade, 30, .12, .95, ch * .35));
    if (e.selfDamage > 0) w.add(_float(t, ac.translate(0, ch * .05), '-${e.selfDamage}', shineEmber, 26, .3, 1, ch * .3));
    return w;
  }

  Widget _skewBanner({required String text, String? sub, required Color color,
    required double dx, required double opacity, double fontSize = 26}) =>
      IgnorePointer(child: Opacity(opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: Transform(
              transform: Matrix4.skewX(-.22), alignment: Alignment.center,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent, color.withValues(alpha: .72),
                      Color.lerp(color, Colors.black, .5)!.withValues(alpha: .92),
                      color.withValues(alpha: .72), Colors.transparent]),
                    border: Border.symmetric(horizontal: BorderSide(
                        color: Colors.white.withValues(alpha: .6), width: 1.4))),
                child: Transform(transform: Matrix4.skewX(.22), alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(text, textAlign: TextAlign.center, style: TextStyle(
                          fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: 5,
                          color: Colors.white, shadows: [Shadow(color: color, blurRadius: 18)])),
                      if (sub != null) Text(sub, style: const TextStyle(fontSize: 11,
                          letterSpacing: 3, color: Colors.white70, fontWeight: FontWeight.w700)),
                    ])),
              )))));

  Widget _turnBanner(Size s) => Positioned(left: 0, right: 0, top: s.height * .08,
      child: AnimatedBuilder(animation: _bannerC, builder: (context, _) {
        if (!_bannerC.isAnimating) return const SizedBox.shrink();
        final p = _bannerC.value;
        final inn = 1 - Curves.easeOutCubic.transform(_seg(p, 0, .2));
        final outt = Curves.easeIn.transform(_seg(p, .78, 1));
        return _skewBanner(text: _turnLabel, sub: 'GILIRAN $turn', color: _accent,
            dx: -s.width * 1.1 * inn + s.width * 1.1 * outt,
            opacity: 1 - outt * .5, fontSize: 26);
      }));

  // ───────────── Header HUD Terpadu (Tanpa Kotak Berlapis) ─────────────

  Widget _centerVsClock() {
    final has = widget.turnDeadline != null && widget.state['winner'] == null;
    final frac = (remainingSeconds / _turnTotal).clamp(0.0, 1.0);
    final urgent = has && remainingSeconds <= 10;
    final color = urgent ? shineEmber : _accent;
    return GestureDetector(
      onTap: _showMenu,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48, height: 48,
            child: Stack(fit: StackFit.expand, children: [
              Container(decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: .55),
                border: Border.all(color: color.withValues(alpha: .4)),
                boxShadow: [BoxShadow(color: color.withValues(alpha: urgent ? .55 : .2), blurRadius: 12)],
              )),
              if (has)
                CircularProgressIndicator(value: frac, strokeWidth: 3.2,
                    backgroundColor: Colors.white10, color: color),
              Center(
                child: has
                    ? Text('$remainingSeconds', style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15, color: color))
                    : Text('G$turn', style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13, color: shineGold)),
              ),
            ]),
          ),
          const SizedBox(height: 3),
          Text(has ? 'GILIRAN $turn' : 'MENU', style: const TextStyle(
              fontSize: 8.5, letterSpacing: 1.5, color: shineMuted, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _broadcastHeader() {
    final over = widget.state['winner'] != null;
    final color = over ? shineGold : _accent;
    return Padding(
      padding: EdgeInsets.fromLTRB(_wide ? 20 : 10, 4, _wide ? 20 : 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Baris tipis navigasi & status giliran
          SizedBox(
            height: 36,
            child: Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Menu pertandingan',
                onPressed: _showMenu,
                icon: const Icon(Icons.menu_rounded, color: shineGold, size: 21),
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: color,
                          boxShadow: [BoxShadow(color: color, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(_turnLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900,
                                letterSpacing: 2.2, color: color)),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.history.isEmpty)
                const SizedBox(width: 40)
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Riwayat pertarungan',
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history_rounded, color: shineGold, size: 20),
                ),
            ]),
          ),
          // Baris Fighter HUD Kiri vs Kanan tanpa kartu kotak
          SizedBox(
            height: _short ? 76 : (_wide ? 92 : 82),
            child: Row(children: [
              Expanded(
                child: _FighterBroadcastHud(
                  team: _team(_left), mirrored: false, accent: shineAzure,
                  label: _sideLabel(_left), big: _wide && !_short,
                  isTurn: !over && activeSide == _left,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _centerVsClock(),
              ),
              Expanded(
                child: _FighterBroadcastHud(
                  team: _team(_right), mirrored: true, accent: shineEmber,
                  label: _sideLabel(_right), big: _wide && !_short,
                  isTurn: !over && activeSide == _right,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stage(Size s) {
    var cw = math.min(s.width * (_wide ? .29 : .35), _wide ? 245.0 : 168.0);
    var ch = cw / .64;
    if (ch > s.height * .84) { ch = s.height * .84; cw = ch * .64; }
    final cy = s.height * .52;
    final sx = _wide ? .32 : .30;
    final lc = Offset(s.width * sx, cy), rc = Offset(s.width * (1 - sx), cy);
    final gap = rc.dx - lc.dx;
    Offset centerOf(int side) => side == _left ? lc : rc;
    return AnimatedBuilder(animation: _fxC, builder: (context, _) {
      final fx = _fxC.isAnimating ? _event : null;
      final t = fx == null ? 0.0 : _fxC.value;
      final shAmt = [0.0, 0.0], shAl = [0.0, 0.0], rsAl = [1.0, 1.0];
      final rs = [0, 0];
      for (var side = 0; side < 2; side++) {
        final tm = _team(side);
        final b = (tm['block'] as num).toInt();
        shAmt[side] = b.toDouble(); shAl[side] = b > 0 ? 1 : 0;
        rs[side] = (tm['reserve'] as num).toInt();
      }
      if (_planning && !busy) {
        final a = activeSide;
        shAmt[a] = defend.toDouble(); shAl[a] = defend > 0 ? .5 : 0;
        rs[a] = reserve; rsAl[a] = .6;
      }
      if (fx != null) {
        if (fx.defend > 0) shAl[fx.actor] = _seg(t, .12, .5);
        if (fx.absorbed > 0) {
          shAmt[fx.target] = fx.oldBlockTarget.toDouble();
          shAl[fx.target] = 1 - _seg(t, .22, .34);
        }
      }
      final aim = _planning && !busy && fx == null && attack > 0 ? attack / 8 : 0.0;
      final poses = [_poseFor(_left, t, fx, gap), _poseFor(_right, t, fx, gap)];
      var shake = Offset.zero;
      double flashA = 0;
      if (fx != null && fx.attacked) {
        final p = _seg(t, .22, .7);
        if (p > 0 && p < 1) {
          final amp = (fx.damage > 0 ? 1.0 : .3) * (2 + 8 * fx.intensity) * (1 - p);
          shake = Offset(math.sin(p * 60) * amp, math.cos(p * 47) * amp * .7);
        }
        if (t >= .22) flashA = (1 - _seg(t, .22, .36)) * (.1 + .24 * fx.intensity);
      }
      final order = fx != null && fx.actor == _left ? [_right, _left] : [_left, _right];
      final skillP = fx != null && fx.skill ? _seg(t, 0, .8) : 0.0;
      return Transform.translate(offset: shake, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: RepaintBoundary(
          child: CustomPaint(painter: _FloorPainter([lc, rc], cw, ch, [shineAzure, shineEmber])),
        )),
        for (final side in order)
          _slot(side, centerOf(side), cw, ch, poses[side == _left ? 0 : 1], fx, t),
        Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
          child: CustomPaint(painter: _StagePainter(
              ambA: _amb, fxA: _fxC, fx: fx, leftSide: _left, centers: [lc, rc],
              cw: cw, ch: ch, shieldAmt: shAmt, shieldAlpha: shAl, reserves: rs,
              reserveAlpha: rsAl, aim: aim, aimSide: 1 - activeSide,
              skillAura: _planning && !busy && skill && fx == null, auraSide: activeSide)),
        ))),
        if (fx != null) ..._floats(t, fx, centerOf, ch),
        if (skillP > 0 && skillP < 1) Positioned(left: 0, right: 0, top: s.height * .36,
            child: _skewBanner(text: fx!.skillName.toUpperCase(), sub: 'SKILL AKTIF',
                color: shineViolet,
                dx: s.width * .9 * (1 - Curves.easeOutCubic.transform(_seg(skillP, 0, .2))),
                opacity: 1 - _seg(skillP, .7, 1))),
        if (flashA > 0) Positioned.fill(child: IgnorePointer(
            child: ColoredBox(color: Colors.white.withValues(alpha: flashA.clamp(0.0, 1.0))))),
        if (aim > 0) Positioned(left: centerOf(1 - activeSide).dx - 60,
            top: centerOf(1 - activeSide).dy - ch / 2 - 10, width: 120,
            child: Center(child: StatPill('~$_previewDamage DMG',
                icon: Icons.flash_on, color: shineEmber))),
        _bench(_left, true), _bench(_right, false),
        _turnBanner(s),
      ]));
    });
  }

  Widget _pips(bool canPlay) {
    final colors = <Color>[
      for (var i = 0; i < attack; i++) shineEmber,
      for (var i = 0; i < defend; i++) shineAzure,
      for (var i = 0; i < reserve; i++) shineGold,
      if (skill) for (var i = 0; i < spec.cost; i++) shineViolet,
    ];
    return Wrap(spacing: 5, runSpacing: 5, children: [
      for (var i = 0; i < available; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 12, height: 12,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: canPlay && i < colors.length ? colors[i] : Colors.transparent,
              border: Border.all(
                  color: canPlay && i < colors.length ? colors[i] : Colors.white24,
                  width: 1.4),
              boxShadow: canPlay && i < colors.length
                  ? [BoxShadow(color: colors[i].withValues(alpha: .5), blurRadius: 6)] : null),
        ),
    ]);
  }

  /// Dek Komando dengan tinggi yang 100% stabil baik saat giliran sendiri maupun giliran lawan.
  /// Mencegah layout jump / patah animasi ketika aksi baru saja dieksekusi.
  Widget _commandDeck(bool canPlay, {bool dock = false}) {
    final cd = (ownCard['cd'] as num).toInt();
    final issue = _issue;
    final left = available - spent;
    final scale = dock ? 1.08 : 1.0;
    final over = widget.state['winner'] != null;

    final String statusHint;
    if (over) {
      statusHint = 'Pertandingan telah berakhir.';
    } else if (!canPlay) {
      statusHint = widget.isBotMatch
          ? 'Komputer sedang mengeksekusi langkah…'
          : 'Menunggu aksi dan sinkronisasi lawan…';
    } else {
      statusHint = issue ?? (skill ? skillText(spec)
          : 'Ketuk heksagon untuk alokasi PA • tahan untuk isi penuh');
    }

    return Container(
      padding: EdgeInsets.fromLTRB(dock ? 20 : 14, dock ? 18 : 8, dock ? 20 : 14, dock ? 18 : 10),
      decoration: dock ? null : BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x000B0A12), Color(0xD90E0C18), Color(0xF5090811)],
              stops: [0.0, 0.22, 1.0]),
          border: Border(top: BorderSide(color: _accent.withValues(alpha: .28)))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Baris Indikator PA & Status
        Row(children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('PA ', style: TextStyle(fontSize: 10, color: shineMuted,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              Text(canPlay ? '$left' : '-', style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900,
                  color: !canPlay ? shineMuted : (left == 0 ? shineJade : (left < 0 ? shineEmber : Colors.white)))),
              Text(' /$available', style: const TextStyle(fontSize: 12.5, color: shineMuted)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(child: _pips(canPlay)),
          IconButton(
            tooltip: 'Atur ulang alokasi PA',
            visualDensity: VisualDensity.compact,
            onPressed: canPlay ? () => setState(reset) : null,
            icon: const Icon(Icons.restart_alt_rounded, color: shineMuted, size: 19),
          ),
        ]),
        // Baris teks petunjuk dengan tinggi konstan (32px) agar tidak mendorong panggung
        SizedBox(
          height: 32,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Row(
                key: ValueKey(statusHint),
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!canPlay && !over) ...[
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: shineGold),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      statusHint,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dock ? 12 : 11,
                        height: 1.25,
                        color: canPlay && issue != null && spent == available
                            ? shineEmber
                            : shineMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: dock ? 12 : 4),
        // Baris Tombol Heksagon — tetap dirender dengan ukuran sama saat giliran lawan
        IgnorePointer(
          ignoring: !canPlay,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 240),
            opacity: canPlay ? 1.0 : 0.42,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HexButton(icon: Icons.inventory_2_outlined, color: const Color(0xFFFF9F1C),
                      label: 'CADANGKAN', count: reserve, enabled: canPlay, scale: scale,
                      onTap: () => _add('r'), onLongPress: () => _add('r', fill: true),
                      onMinus: () => setState(() => reserve--)),
                  const SizedBox(width: 8),
                  _HexButton(icon: Icons.shield, color: const Color(0xFF2E7DFF),
                      label: 'BERTAHAN', count: defend, enabled: canPlay, scale: scale,
                      onTap: () => _add('d'), onLongPress: () => _add('d', fill: true),
                      onMinus: () => setState(() => defend--)),
                  const SizedBox(width: 8),
                  _HexButton(icon: Icons.flash_on, color: const Color(0xFFE53545),
                      label: 'SERANG', count: attack, enabled: canPlay, scale: scale,
                      onTap: () => _add('a'), onLongPress: () => _add('a', fill: true),
                      onMinus: () => setState(() => attack--)),
                  const SizedBox(width: 8),
                  _HexButton(icon: Icons.auto_awesome, color: const Color(0xFF8E5BFF),
                      label: spec.skill.toUpperCase(), count: skill ? 1 : 0, scale: scale,
                      badgeText: skill ? '✓' : '${spec.cost}PA', cooldown: cd,
                      enabled: canPlay && cd == 0, onTap: () => _toggleSkill(!skill)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: dock ? 16 : 8),
        ShineButton(
          icon: canPlay ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
          label: canPlay ? 'JALANKAN AKSI' : _turnLabel,
          height: dock ? 54 : 46,
          onPressed: issue == null && canPlay ? () => submit() : null,
        ),
      ]),
    );
  }

  Widget _dock(bool canPlay) => Container(
    width: 390,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .32),
      border: Border(left: BorderSide(color: _accent.withValues(alpha: .32))),
    ),
    child: SafeArea(
      left: false,
      child: Center(
        child: SingleChildScrollView(
          child: _commandDeck(canPlay, dock: true),
        ),
      ),
    ),
  );

  Widget _resultOverlay(int w) {
    final won = w == widget.viewerSide;
    final bad = _personal && !won;
    final color = bad ? shineEmber : shineGold;
    final title = _personal ? (won ? 'KEMENANGAN' : 'KEKALAHAN')
        : 'TIM ${w == 0 ? 'A' : 'B'} MENANG';
    final sub = !_personal ? 'Pertandingan selesai.'
        : (won ? 'Seluruh tokoh lawan telah tumbang.' : 'Seluruh tokohmu tumbang. Coba strategi lain!');
    return Positioned.fill(child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(opacity: v.clamp(0.0, 1.0),
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .76))),
            Positioned.fill(child: CustomPaint(painter: _RaysPainter(_amb, color, !bad))),
            Center(child: Transform.scale(scale: .85 + .15 * v, child: child)),
          ])),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(padding: const EdgeInsets.all(28), child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(bad ? Icons.heart_broken : Icons.emoji_events, color: color, size: 72, shadows: [
              Shadow(color: color, blurRadius: 30)]),
            const SizedBox(height: 8),
            ShaderMask(
                shaderCallback: (r) => LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.white, .6)!, color]).createShader(r),
                child: Text(title, textAlign: TextAlign.center, style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6,
                    color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 14)]))),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center,
                style: const TextStyle(color: shineMuted, fontSize: 13)),
            const SizedBox(height: 12),
            Center(child: StatPill('Berakhir di giliran $turn',
                icon: Icons.timelapse, color: color)),
            const SizedBox(height: 26),
            if (widget.onReplay != null) ...[
              ShineButton(icon: Icons.replay, label: 'MAIN LAGI', onPressed: widget.onReplay),
              const SizedBox(height: 10),
            ],
            ShineButton(primary: widget.onReplay == null, icon: Icons.home_outlined,
                label: 'KEMBALI KE MENU', onPressed: () => Navigator.of(context).pop()),
          ]))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final winner = widget.state['winner'];
    final canPlay = widget.canAct && winner == null && !busy;
    return ShineScaffold(
      accent: _accent,
      body: Stack(children: [
        Positioned.fill(child: RepaintBoundary(
          child: CustomPaint(painter: _ScenePainter(_amb, _accent)),
        )),
        SafeArea(bottom: false, child: LayoutBuilder(builder: (context, box) {
          _wide = shineIsWide(box.biggest);
          _short = box.maxHeight < 520;
          final stage = Column(children: [
            _broadcastHeader(),
            Expanded(child: LayoutBuilder(builder: (context, b) => _stage(b.biggest))),
          ]);
          if (_wide) {
            return Row(children: [
              Expanded(child: stage),
              _dock(canPlay),
            ]);
          }
          return Column(children: [
            Expanded(child: stage),
            SafeArea(top: false, child: _commandDeck(canPlay)),
          ]);
        })),
        if (winner != null && _resultReady) _resultOverlay((winner as num).toInt()),
      ]),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.amb, this.color, this.rays) : super(repaint: amb);
  final Animation<double> amb;
  final Color color;
  final bool rays;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .38);
    canvas.drawCircle(c, size.width * .8, Paint()..shader = RadialGradient(
        colors: [color.withValues(alpha: .3), Colors.transparent])
        .createShader(Rect.fromCircle(center: c, radius: size.width * .8)));
    if (!rays) return;
    for (var i = 0; i < 14; i++) {
      final a = amb.value * math.pi * 2 / 3 + i * math.pi * 2 / 14;
      final p = Path()..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - .05) * size.height, c.dy + math.sin(a - .05) * size.height)
        ..lineTo(c.dx + math.cos(a + .05) * size.height, c.dy + math.sin(a + .05) * size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = color.withValues(alpha: .07));
    }
  }
  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.color != color;
}