import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/characters.dart';
import 'how_to_play.dart';
import 'menu_page.dart';
import 'shine_ui.dart';

/// Beranda awal: satu momen dramatis (kipas kartu bercahaya) + satu ajakan
/// bertindak. Semua pilihan mode ada di [ShineMenuPage].
class ShineLandingPage extends StatefulWidget {
  const ShineLandingPage({super.key});
  @override
  State<ShineLandingPage> createState() => _ShineLandingPageState();
}

class _ShineLandingPageState extends State<ShineLandingPage> {
  /// Posisi kursor/jari ternormalisasi (-1..1) untuk efek paralaks kartu.
  final ValueNotifier<Offset> _look = ValueNotifier(Offset.zero);

  @override
  void dispose() { _look.dispose(); super.dispose(); }

  void _start() =>
      Navigator.of(context).push(shineRoute<void>(const ShineMenuPage()));

  void _track(PointerEvent e, Size size) {
    if (size.isEmpty) return;
    _look.value = Offset(
      (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): _start,
      const SingleActivator(LogicalKeyboardKey.space): _start,
    },
    child: Focus(
      autofocus: true,
      child: ShineScaffold(
        embers: true,
        body: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          final wide = shineIsWide(size);
          final copy = _LandingCopy(
            wide: wide,
            onStart: _start,
            onHelp: () => showHowToPlay(context),
          );
          final fan = _CardFan(look: _look);
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (e) => _track(e, size),
            onPointerMove: (e) => _track(e, size),
            child: SafeArea(
              child: Stack(children: [
                Positioned.fill(
                  child: wide
                      ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 28),
                    child: Center(child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Row(children: [
                        Expanded(flex: 5, child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 440, child: copy),
                          ),
                        )),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: fan),
                      ]),
                    )),
                  )
                      : Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
                    child: Center(child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(children: [
                        Expanded(child: fan),
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(width: 360, child: copy),
                        ),
                      ]),
                    )),
                  ),
                ),
                const Positioned(
                  left: 0, right: 0, bottom: 6,
                  child: IgnorePointer(child: Text(
                    'v1.1 • prototipe playtest',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Colors.white24,
                        letterSpacing: 1.2),
                  )),
                ),
              ]),
            ),
          );
        }),
      ),
    ),
  );
}

// ───────────── Teks & tombol ─────────────

class _LandingCopy extends StatelessWidget {
  const _LandingCopy({required this.wide, required this.onStart, required this.onHelp});
  final bool wide;
  final VoidCallback onStart, onHelp;

  @override
  Widget build(BuildContext context) {
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    final buttonWidth = wide ? 340.0 : double.infinity;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        ShineWordmark(size: wide ? 96 : 64),
        const SizedBox(height: 12),
        const Text('MANHWA CARD BATTLE', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800, letterSpacing: 5, color: shineMuted)),
        const SizedBox(height: 18),
        Text(
          'Susun tiga tokoh, bagi Poin Aksi, lalu tumbangkan lawanmu '
              'dalam duel kartu satu lawan satu.',
          textAlign: textAlign,
          style: TextStyle(fontSize: wide ? 16 : 14, height: 1.5,
              color: Colors.white70),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: const [
            StatPill('26 TOKOH', icon: Icons.person_outline, color: shineGold),
            StatPill('3 KARTU', icon: Icons.style_outlined, color: shineGold),
            StatPill('1 vs 1', icon: Icons.bolt, color: shineGold),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(width: buttonWidth, child: _PulseGlow(
          child: ShineButton(
            icon: Icons.play_arrow_rounded, label: 'MULAI BERMAIN',
            height: 62, onPressed: onStart,
          ),
        )),
        const SizedBox(height: 12),
        SizedBox(width: buttonWidth, child: ShineButton(
          primary: false, icon: Icons.menu_book_outlined,
          label: 'CARA BERMAIN', height: 50, onPressed: onHelp,
        )),
        if (wide) const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Text('atau tekan Enter', style: TextStyle(
              fontSize: 12, color: Colors.white38, letterSpacing: .6)),
        ),
      ],
    );
  }
}

/// Cahaya emas berdenyut di sekeliling tombol utama.
class _PulseGlow extends StatefulWidget {
  const _PulseGlow({required this.child});
  final Widget child;
  @override
  State<_PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<_PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _started = false;
    } else if (!_started) {
      _c.repeat(reverse: true);
      _started = true;
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = Curves.easeInOut.transform(_c.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: shineGold.withValues(alpha: .12 + .24 * v),
            blurRadius: 22 + 22 * v, spreadRadius: 1 + 3 * v,
          )],
        ),
        child: child,
      );
    },
  );
}

// ───────────── Kipas kartu ─────────────

class _CardFan extends StatefulWidget {
  const _CardFan({required this.look});
  final ValueNotifier<Offset> look;
  @override
  State<_CardFan> createState() => _CardFanState();
}

class _CardFanState extends State<_CardFan> with TickerProviderStateMixin {
  static const _ids = <String>[
    'kurokawaren', 'baekseoyeon', 'chaminhyuk', 'ragnarsigurdsson', 'linzixuan',
  ];

  // (posisi x dalam lebar kartu, sudut, turun dalam tinggi kartu, skala, kedalaman)
  static const _layout = <(double, double, double, double, double)>[
    (-.98, -.20, .09, .84, .5),
    (-.50, -.10, .035, .92, .8),
    (0.0, 0.0, 0.0, 1.0, 1.2),
    (.50, .10, .035, .92, .8),
    (.98, .20, .09, .84, .5),
  ];

  // Pengali jarak antarkartu (lebih kecil = kartu lebih rapat & lebih besar).
  static const _spread = .8;

  // Urutan lukis: kartu terluar dahulu, kartu tengah paling atas.
  static const _paintOrder = <int>[0, 4, 1, 3, 2];

  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(seconds: 7));
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700));
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _intro.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _bob.stop();
      _intro.value = 1;
      _started = false;
    } else if (!_started) {
      _bob.repeat();
      _started = true;
    }
  }

  @override
  void dispose() { _bob.dispose(); _intro.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final w = box.maxWidth, h = box.maxHeight;
    final ch = math.min(h * .72, w / (1.96 * _spread + .9) / .64);
    final cw = ch * .64;
    return SizedBox(
      width: w, height: h,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bob, _intro, widget.look]),
        builder: (context, _) {
          final t = _bob.value;
          final look = widget.look.value;
          return Stack(clipBehavior: Clip.none, children: [
            // Cahaya panggung di belakang kartu.
            Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(gradient: RadialGradient(
                center: const Alignment(0, -.05), radius: .72,
                colors: [shineGold.withValues(alpha: .24), Colors.transparent],
              )),
            )),
            // Bayangan lantai.
            Positioned(
              left: (w - cw * 2.9) / 2,
              top: h / 2 + ch / 2 - ch * .02,
              width: cw * 2.9, height: ch * .14,
              child: const CustomPaint(painter: _FloorGlow()),
            ),
            for (final i in _paintOrder) _card(i, w, h, cw, ch, t, look),
          ]);
        },
      ),
    );
  });

  Widget _card(int i, double w, double h, double cw, double ch, double t,
      Offset look) {
    final (x, angle, drop, sc, depth) = _layout[i];
    final delay = (i - 2).abs() * .12;
    final e = Curves.easeOutBack
        .transform(((_intro.value - delay) / .6).clamp(0.0, 1.0));
    final cardW = cw * sc, cardH = ch * sc;
    final bob = math.sin(t * math.pi * 2 + i * 1.3) * ch * .012;
    final left = w / 2 + x * _spread * cw + look.dx * 14 * depth - cardW / 2;
    final top = h / 2 + drop * ch + bob + look.dy * 8 * depth - cardH / 2 +
        (1 - e) * ch * .5;
    return Positioned(
      left: left, top: top, width: cardW, height: cardH,
      child: Opacity(
        opacity: e.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle * e + look.dx * .015 * depth,
          child: _FanCard(spec: characterById(_ids[i]), hero: i == 2),
        ),
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  const _FanCard({required this.spec, required this.hero});
  final CharacterSpec spec;
  final bool hero;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final nameSize = (box.maxWidth * .085).clamp(9.0, 17.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (hero) BoxShadow(color: shineGold.withValues(alpha: .45),
              blurRadius: 40, spreadRadius: -4),
          BoxShadow(color: Colors.black.withValues(alpha: .65),
              blurRadius: 24, offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(fit: StackFit.expand, children: [
        Portrait(spec, radius: 18),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: const [.6, 1],
            colors: [Colors.transparent, Colors.black.withValues(alpha: .88)],
          ),
        ))),
        Positioned(left: 8, right: 8, bottom: 10, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(spec.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center, style: TextStyle(
                    fontSize: nameSize, fontWeight: FontWeight.w900,
                    letterSpacing: .5)),
            if (hero) Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(spec.skill, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: nameSize * .72, color: shineGold)),
            ),
          ],
        )),
      ]),
    );
  });
}

class _FloorGlow extends CustomPainter {
  const _FloorGlow();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, size.height / size.width);
    final radius = size.width / 2;
    canvas.drawCircle(Offset.zero, radius, Paint()
      ..shader = RadialGradient(colors: [
        shineGold.withValues(alpha: .38), Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
