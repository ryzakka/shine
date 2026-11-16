import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/characters.dart';

// ───────────── Design tokens ─────────────
const shineGold = Color(0xFFEFC483);
const shineGoldLight = Color(0xFFFFE5B4);
const shineGoldDeep = Color(0xFFC48B37);
const shineMuted = Color(0xFF9E99B3);
const shineInk = Color(0xFF0B0A12);
const shinePanel = Color(0xFF161322);
const shineEmber = Color(0xFFFF4D5E); // lawan / serang / bahaya
const shineAzure = Color(0xFF47B8FF); // pemain / bertahan
const shineJade = Color(0xFF45E09B); // siap / pulih
const shineViolet = Color(0xFFB580FF); // skill

String skillKindLabel(String kind) => switch (kind) {
  'damage' => 'Damage bonus',
  'pierce' => 'Tembus pertahanan',
  'heal' => 'Pemulihan',
  'heal_all' => 'Pemulihan tim',
  'shield' => 'Pertahanan',
  'reserve' => 'Cadangan PA',
  'drain' => 'Kuras PA lawan',
  'recoil' => 'Serangan nekat',
  'conditional_damage' => 'Damage bersyarat',
  'hybrid' => 'Serang + bertahan',
  _ => 'Skill',
};

String skillText(CharacterSpec s) {
  switch (s.kind) {
    case 'damage':
      return '+${s.value} damage bila serangan mengenai.';
    case 'pierce':
      return 'Serangan menembus ${s.value} PA pertahanan lawan.';
    case 'heal':
      return 'Memulihkan ${s.value} HP tokoh aktif.';
    case 'heal_all':
      return 'Memulihkan ${s.value} HP seluruh tokoh yang hidup.';
    case 'shield':
      return '+${s.value} PA pertahanan gratis.';
    case 'reserve':
      return '+${s.value} PA cadangan gratis.';
    case 'drain':
      return 'Menguras ${s.value} PA cadangan lawan.';
    case 'recoil':
      return '+${s.value} damage, tetapi melukai diri ${s.aux} HP.';
    case 'conditional_damage':
      return s.aux > 0
          ? '+${s.value} damage bila memakai minimal ${s.aux} PA serang.'
          : '+${s.value} damage bila lawan tidak bertahan.';
    case 'hybrid':
      return '+${s.value} damage dan +${s.aux} PA pertahanan.';
  }
  return s.skill;
}

// ───────────── Responsif & transisi ─────────────

bool shineIsWide(Size s) =>
    s.width >= 880 || (s.width >= 640 && s.width > s.height * 1.22);

Route<T> shineRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (context, anim, secondary, child) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .03), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  },
);

double _fr(double v) => v - v.floorToDouble();

// ───────────── Layout & Atmosfer ─────────────

class ShineBackdrop extends StatelessWidget {
  const ShineBackdrop({super.key, this.accent = shineGold});
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF17122B), shineInk, Color(0xFF06050A)],
        stops: [0.0, 0.55, 1.0],
      ),
    ),
    child: TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 650),
      builder: (context, color, _) {
        final activeColor = color ?? accent;
        return Stack(children: [
          Positioned(
            top: -180, left: -100, right: -100, height: 480,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.85,
                  colors: [
                    activeColor.withValues(alpha: .20),
                    activeColor.withValues(alpha: .04),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -220, left: -120, right: -120, height: 440,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    shineViolet.withValues(alpha: .09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
    ),
  );
}

class ShineScaffold extends StatelessWidget {
  const ShineScaffold({super.key, required this.body, this.appBar,
    this.accent = shineGold, this.embers = false});
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color accent;
  final bool embers;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: RepaintBoundary(child: ShineBackdrop(accent: accent))),
    if (embers) const Positioned.fill(child: IgnorePointer(child: ShineEmbers())),
    Scaffold(backgroundColor: Colors.transparent, appBar: appBar, body: body),
  ]);
}

class ShineEmbers extends StatefulWidget {
  const ShineEmbers({super.key, this.color = shineGold, this.count = 30});
  final Color color;
  final int count;
  @override
  State<ShineEmbers> createState() => _ShineEmbersState();
}

class _ShineEmbersState extends State<ShineEmbers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(seconds: 26));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _started = false;
    } else if (!_started) {
      _c.repeat();
      _started = true;
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _EmberPainter(_c, widget.color, widget.count),
    ),
  );
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.t, this.color, this.count) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final speed = 1 + (i % 4);
      final prog = (_fr(i * .7549) + t.value * speed) % 1.0;
      final x = _fr(i * .6180339) * size.width +
          math.sin(t.value * math.pi * 2 * speed + i) * 16;
      final y = size.height * (1 - prog);
      final r = .7 + 1.6 * _fr(i * .37);
      final a = math.sin(prog * math.pi) * (.14 + .32 * _fr(i * .91));
      paint.color = color.withValues(alpha: a * .20);
      canvas.drawCircle(Offset(x, y), r * 3.4, paint);
      paint.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter old) =>
      old.color != color || old.count != count;
}

class ShineWordmark extends StatefulWidget {
  const ShineWordmark({super.key, this.size = 58});
  final double size;
  @override
  State<ShineWordmark> createState() => _ShineWordmarkState();
}

class _ShineWordmarkState extends State<ShineWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _c.value = .45;
      _started = false;
    } else if (!_started) {
      _c.repeat();
      _started = true;
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final spacing = widget.size * .22;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final p = Curves.easeInOut.transform(_c.value);
          return Padding(
            padding: EdgeInsets.only(left: spacing),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment(-3.2 + 5.4 * p, -.4),
                end: Alignment(-1.2 + 5.4 * p, .4),
                colors: const [shineGold, shineGoldLight, Colors.white,
                  shineGoldLight, shineGold],
                stops: const [0, .3, .5, .7, 1],
              ).createShader(r),
              child: Text('SHINE', style: TextStyle(
                fontSize: widget.size, fontWeight: FontWeight.w900,
                letterSpacing: spacing, height: 1, color: Colors.white,
                shadows: [Shadow(
                    color: shineGold.withValues(alpha: .55),
                    blurRadius: widget.size * .45)],
              )),
            ),
          );
        },
      ),
    );
  }
}

class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 400 + index * 75),
    curve: Curves.easeOutCubic,
    builder: (context, v, c) => Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.top = 24});
  final String text;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 10),
    child: Row(children: [
      Container(
        width: 3, height: 12,
        decoration: BoxDecoration(
            color: shineGold, borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: shineGold.withValues(alpha: .6), blurRadius: 6)]),
      ),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: shineGold,
          fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 10.5)),
      Expanded(child: Container(
        height: 1, margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [
          shineGold.withValues(alpha: .28), Colors.transparent])),
      )),
      if (trailing != null) ...[const SizedBox(width: 10), trailing!],
    ]),
  );
}

/// Permukaan halus hanya untuk elemen interaktif yang benar-benar butuh batas.
class ShinePanel extends StatelessWidget {
  const ShinePanel({super.key, required this.child,
    this.padding = const EdgeInsets.all(16), this.glow, this.borderColor,
    this.radius = 18, this.onTap, this.tint});
  final Widget child;
  final EdgeInsets padding;
  final Color? glow, borderColor, tint;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            tint != null
                ? Color.alphaBlend(tint!.withValues(alpha: .12), const Color(0xCC211C30))
                : const Color(0xCC211C30),
            const Color(0xCC120F1D),
          ],
        ),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: .07)),
        boxShadow: [
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: .22), blurRadius: 24, spreadRadius: -6),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r, onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class ShineButton extends StatelessWidget {
  const ShineButton({super.key, required this.label, required this.onPressed,
    this.icon, this.subtitle, this.primary = true, this.height = 54});
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = primary ? const Color(0xFF1F1505) : shineGold;
    final r = BorderRadius.circular(14);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .38,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: primary
              ? const LinearGradient(colors: [shineGoldLight, shineGold, shineGoldDeep],
              begin: Alignment.topCenter, end: Alignment.bottomCenter)
              : null,
          color: primary ? null : Colors.white.withValues(alpha: .04),
          border: primary ? null : Border.all(color: shineGold.withValues(alpha: .42)),
          boxShadow: primary && enabled
              ? [BoxShadow(color: shineGold.withValues(alpha: .32),
              blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 4))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: r, onTap: onPressed,
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: fg, size: 21), const SizedBox(width: 9)],
                Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, textAlign: TextAlign.center, style: TextStyle(
                      color: fg, fontWeight: FontWeight.w900,
                      letterSpacing: 1.4, fontSize: 13.5)),
                  if (subtitle != null)
                    Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(
                        color: fg.withValues(alpha: .75), fontSize: 10.5)),
                ])),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill(this.text, {super.key, this.icon, this.color = shineMuted});
  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .32)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
      Text(text, style: TextStyle(
          color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .4)),
    ]),
  );
}

// ───────────── Karakter & Bar HP Dramatis ─────────────

class Portrait extends StatelessWidget {
  const Portrait(this.spec, {super.key, this.width, this.height,
    this.radius = 12, this.border = true, this.fit = BoxFit.cover,
    this.borderColor});
  final CharacterSpec spec;
  final double? width, height;
  final double radius;
  final bool border;
  final BoxFit fit;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: border
          ? Border.all(color: (borderColor ?? shineGold).withValues(alpha: .75), width: 1.3)
          : null,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius > 1.3 ? radius - 1.3 : radius),
      child: Image.asset(spec.asset, fit: fit, alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF231E30), alignment: Alignment.center,
            child: Text(spec.name.substring(0, 1), style: const TextStyle(
                color: shineGold, fontWeight: FontWeight.w900, fontSize: 22)),
          )),
    ),
  );
}

class HpBar extends StatelessWidget {
  const HpBar({super.key, required this.hp, required this.maxHp,
    this.height = 10, this.showText = false, this.mirrored = false});
  final int hp, maxHp;
  final double height;
  final bool showText;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final f = maxHp == 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: f),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final c = v > .5 ? shineJade : (v > .25 ? const Color(0xFFFFB84D) : shineEmber);
        return Transform(
          transform: Matrix4.skewX(mirrored ? .22 : -.22),
          alignment: Alignment.center,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(children: [
                Align(
                  alignment: mirrored ? Alignment.centerRight : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: mirrored
                              ? [c, c.withValues(alpha: .7)]
                              : [c.withValues(alpha: .7), c],
                        ),
                        boxShadow: [BoxShadow(color: c.withValues(alpha: .6), blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
                if (showText) Center(child: Text('$hp / $maxHp', style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 3)]))),
              ]),
            ),
          ),
        );
      },
    );
  }
}