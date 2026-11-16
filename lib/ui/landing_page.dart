import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/characters.dart';
import 'how_to_play.dart';
import 'menu_page.dart';
import 'shine_ui.dart';

class ShineLandingPage extends StatefulWidget {
  const ShineLandingPage({super.key});
  @override
  State<ShineLandingPage> createState() => _ShineLandingPageState();
}

class _ShineLandingPageState extends State<ShineLandingPage> {
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
                        horizontal: 56, vertical: 28),
                    child: Center(child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1260),
                      child: Row(children: [
                        Expanded(flex: 5, child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(width: 450, child: copy),
                          ),
                        )),
                        const SizedBox(width: 32),
                        Expanded(flex: 7, child: fan),
                      ]),
                    )),
                  )
                      : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    child: Center(child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(children: [
                        Expanded(child: fan),
                        const SizedBox(height: 16),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(width: 360, child: copy),
                        ),
                      ]),
                    )),
                  ),
                ),
                Positioned(
                  top: 8, right: 16,
                  child: TextButton.icon(
                    onPressed: () => showHowToPlay(context),
                    style: TextButton.styleFrom(foregroundColor: shineMuted),
                    icon: const Icon(Icons.menu_book_outlined, size: 16, color: shineGold),
                    label: const Text('PANDUAN', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    ),
  );
}

class _LandingCopy extends StatelessWidget {
  const _LandingCopy({required this.wide, required this.onStart, required this.onHelp});
  final bool wide;
  final VoidCallback onStart, onHelp;

  @override
  Widget build(BuildContext context) {
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 24, height: 1.5, color: shineGold),
            const SizedBox(width: 10),
            const Text('TACTICAL MANHWA DUEL', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w900,
                letterSpacing: 4.5, color: shineGold)),
            if (!wide) ...[
              const SizedBox(width: 10),
              Container(width: 24, height: 1.5, color: shineGold),
            ],
          ],
        ),
        const SizedBox(height: 14),
        ShineWordmark(size: wide ? 104 : 68),
        const SizedBox(height: 18),
        Text(
          'Pilih tiga petarung, kelola Poin Aksi setiap giliran, dan '
              'tumbangkan formasi lawan dalam pertarungan taktis satu lawan satu.',
          textAlign: textAlign,
          style: TextStyle(fontSize: wide ? 16 : 14, height: 1.55,
              color: Colors.white.withValues(alpha: .78)),
        ),
        const SizedBox(height: 22),
        // Baris spesifikasi terbuka tanpa kotak-kotak berlebih
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetaItem('26', 'TOKOH'),
            _dot(),
            _MetaItem('3v3', 'SKUAD'),
            _dot(),
            _MetaItem('1v1', 'ARENA'),
          ],
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: wide ? 340.0 : double.infinity,
          child: _PulseGlow(
            child: ShineButton(
              icon: Icons.play_arrow_rounded, label: 'MASUKI ARENA',
              height: 60, onPressed: onStart,
            ),
          ),
        ),
        if (wide) const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Text('Tekan [Enter] atau [Spasi] untuk langsung mulai',
              style: TextStyle(fontSize: 11.5, color: Colors.white38, letterSpacing: .5)),
        ),
      ],
    );
  }

  Widget _dot() => Container(
    width: 4, height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(color: shineGold, shape: BoxShape.circle),
  );
}

class _MetaItem extends StatelessWidget {
  const _MetaItem(this.val, this.label);
  final String val, label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
          color: shineGoldLight, letterSpacing: .5)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800,
          color: shineMuted, letterSpacing: 2)),
    ],
  );
}

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
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: shineGold.withValues(alpha: .14 + .24 * v),
            blurRadius: 24 + 20 * v, spreadRadius: 1 + 2 * v,
          )],
        ),
        child: child,
      );
    },
  );
}

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

  static const _layout = <(double, double, double, double, double)>[
    (-.98, -.20, .09, .84, .5),
    (-.50, -.10, .035, .92, .8),
    (0.0, 0.0, 0.0, 1.0, 1.2),
    (.50, .10, .035, .92, .8),
    (.98, .20, .09, .84, .5),
  ];

  static const _spread = .82;
  static const _paintOrder = <int>[0, 4, 1, 3, 2];

  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(seconds: 7));
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
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
    final ch = math.min(h * .76, w / (1.96 * _spread + .85) / .64);
    final cw = ch * .64;
    return RepaintBoundary(
      child: SizedBox(
        width: w, height: h,
        child: AnimatedBuilder(
          animation: Listenable.merge([_bob, _intro, widget.look]),
          builder: (context, _) {
            final t = _bob.value;
            final look = widget.look.value;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: DecoratedBox(
                decoration: BoxDecoration(gradient: RadialGradient(
                  center: const Alignment(0, -.05), radius: .75,
                  colors: [shineGold.withValues(alpha: .22), Colors.transparent],
                )),
              )),
              Positioned(
                left: (w - cw * 3.0) / 2,
                top: h / 2 + ch / 2 - ch * .02,
                width: cw * 3.0, height: ch * .14,
                child: const CustomPaint(painter: _FloorGlow()),
              ),
              for (final i in _paintOrder) _card(i, w, h, cw, ch, t, look),
            ]);
          },
        ),
      ),
    );
  });

  Widget _card(int i, double w, double h, double cw, double ch, double t,
      Offset look) {
    final (x, angle, drop, sc, depth) = _layout[i];
    final delay = (i - 2).abs() * .11;
    final e = Curves.easeOutBack
        .transform(((_intro.value - delay) / .6).clamp(0.0, 1.0));
    final cardW = cw * sc, cardH = ch * sc;
    final bob = math.sin(t * math.pi * 2 + i * 1.3) * ch * .012;
    final left = w / 2 + x * _spread * cw + look.dx * 16 * depth - cardW / 2;
    final top = h / 2 + drop * ch + bob + look.dy * 9 * depth - cardH / 2 +
        (1 - e) * ch * .45;
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
          if (hero) BoxShadow(color: shineGold.withValues(alpha: .42),
              blurRadius: 42, spreadRadius: -4),
          BoxShadow(color: Colors.black.withValues(alpha: .7),
              blurRadius: 24, offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(fit: StackFit.expand, children: [
        Portrait(spec, radius: 18),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: const [.55, 1],
            colors: [Colors.transparent, Colors.black.withValues(alpha: .9)],
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
        shineGold.withValues(alpha: .36), Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}