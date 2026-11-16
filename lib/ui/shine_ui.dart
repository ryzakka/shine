import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/characters.dart';

// ───────────── Design tokens ─────────────
const shineGold = Color(0xFFEFC483);
const shineGoldLight = Color(0xFFFFE2A8);
const shineGoldDeep = Color(0xFFC99643);
const shineMuted = Color(0xFFAAA5BE);
const shineInk = Color(0xFF10101B);
const shinePanel = Color(0xFF1B1828);
const shineEmber = Color(0xFFFF5A64); // lawan / serang / bahaya
const shineAzure = Color(0xFF5CC8FF); // pemain / bertahan
const shineJade = Color(0xFF59E0A0); // siap / pulih
const shineViolet = Color(0xFFB48CFF); // skill

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

/// Tata letak lebar (desktop, tablet, ponsel landscape) memakai dua kolom.
bool shineIsWide(Size s) =>
    s.width >= 900 || (s.width >= 640 && s.width > s.height * 1.25);

/// Transisi halaman seragam: memudar sambil naik sedikit.
Route<T> shineRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 420),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (context, anim, secondary, child) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  },
);

double _fr(double v) => v - v.floorToDouble();

// ───────────── Layout ─────────────

/// Latar dramatis: gradasi gelap dengan cahaya aksen di bagian atas.
class ShineBackdrop extends StatelessWidget {
  const ShineBackdrop({super.key, this.accent = shineGold});
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A1530), shineInk, Color(0xFF08080F)],
      ),
    ),
    child: TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 600),
      builder: (context, color, _) => Stack(children: [
        Positioned(
          top: -150, left: -80, right: -80, height: 420,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                (color ?? accent).withValues(alpha: .22),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: -200, left: -120, right: -120, height: 420,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                shineViolet.withValues(alpha: .10),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ]),
    ),
  );
}

/// Scaffold transparan di atas [ShineBackdrop] agar AppBar menyatu dengan latar.
/// [embers] menambahkan percikan cahaya yang naik perlahan (beranda & menu).
class ShineScaffold extends StatelessWidget {
  const ShineScaffold({super.key, required this.body, this.appBar,
    this.accent = shineGold, this.embers = false});
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color accent;
  final bool embers;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: ShineBackdrop(accent: accent)),
    if (embers) const Positioned.fill(child: IgnorePointer(child: ShineEmbers())),
    Scaffold(backgroundColor: Colors.transparent, appBar: appBar, body: body),
  ]);
}

/// Percikan emas yang naik perlahan. Berhenti bila animasi dimatikan sistem.
class ShineEmbers extends StatefulWidget {
  const ShineEmbers({super.key, this.color = shineGold, this.count = 34});
  final Color color;
  final int count;
  @override
  State<ShineEmbers> createState() => _ShineEmbersState();
}

class _ShineEmbersState extends State<ShineEmbers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));
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
          math.sin(t.value * math.pi * 2 * speed + i) * 14;
      final y = size.height * (1 - prog);
      final r = .8 + 1.8 * _fr(i * .37);
      final a = math.sin(prog * math.pi) * (.16 + .34 * _fr(i * .91));
      paint.color = color.withValues(alpha: a * .22);
      canvas.drawCircle(Offset(x, y), r * 3.2, paint);
      paint.color = color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter old) =>
      old.color != color || old.count != count;
}

/// Logo SHINE dengan kilau emas yang menyapu huruf secara berkala.
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
    final spacing = widget.size * .2;
    return AnimatedBuilder(
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
                  color: shineGold.withValues(alpha: .6),
                  blurRadius: widget.size * .5)],
            )),
          ),
        );
      },
    );
  }
}

/// Muncul perlahan dari bawah; [index] memberi jeda antar-bagian.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 450 + index * 90),
    curve: Curves.easeOutCubic,
    builder: (context, v, c) => Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: c),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Row(children: [
      Container(
        width: 3, height: 13,
        decoration: BoxDecoration(
            color: shineGold, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: shineGold,
          fontWeight: FontWeight.w900, letterSpacing: 2.2, fontSize: 11)),
      Expanded(child: Container(
        height: 1, margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [
          shineGold.withValues(alpha: .35), Colors.transparent])),
      )),
      if (trailing != null) ...[const SizedBox(width: 10), trailing!],
    ]),
  );
}

class ShinePanel extends StatelessWidget {
  const ShinePanel({super.key, required this.child,
    this.padding = const EdgeInsets.all(16), this.glow, this.borderColor,
    this.radius = 20, this.onTap, this.tint});
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
                ? Color.alphaBlend(tint!.withValues(alpha: .14), const Color(0xFF262136))
                : const Color(0xFF262136),
            const Color(0xFF181525),
          ],
        ),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: .08)),
        boxShadow: [
          if (glow != null)
            BoxShadow(color: glow!.withValues(alpha: .28), blurRadius: 26, spreadRadius: -4),
          BoxShadow(color: Colors.black.withValues(alpha: .35),
              blurRadius: 16, offset: const Offset(0, 8)),
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
    this.icon, this.subtitle, this.primary = true, this.height = 56});
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = primary ? const Color(0xFF241A08) : shineGold;
    final r = BorderRadius.circular(16);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : .42,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: primary
              ? const LinearGradient(colors: [shineGoldLight, shineGold, shineGoldDeep],
              begin: Alignment.topCenter, end: Alignment.bottomCenter)
              : null,
          color: primary ? null : Colors.white.withValues(alpha: .05),
          border: primary ? null : Border.all(color: shineGold.withValues(alpha: .5)),
          boxShadow: primary && enabled
              ? [BoxShadow(color: shineGold.withValues(alpha: .38),
              blurRadius: 24, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: r, onTap: onPressed,
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 10)],
                Flexible(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, textAlign: TextAlign.center, style: TextStyle(
                      color: fg, fontWeight: FontWeight.w900,
                      letterSpacing: 1.3, fontSize: 14)),
                  if (subtitle != null)
                    Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(
                        color: fg.withValues(alpha: .75), fontSize: 11)),
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
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .38)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
      Text(text, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ───────────── Karakter ─────────────

class Portrait extends StatelessWidget {
  const Portrait(this.spec, {super.key, this.width, this.height,
    this.radius = 12, this.border = true, this.fit = BoxFit.cover});
  final CharacterSpec spec;
  final double? width, height;
  final double radius;
  final bool border;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: border
          ? Border.all(color: shineGold.withValues(alpha: .8), width: 1.4)
          : null,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius > 1.4 ? radius - 1.4 : radius),
      child: Image.asset(spec.asset, fit: fit, alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF2A2438), alignment: Alignment.center,
            child: Text(spec.name.substring(0, 1), style: const TextStyle(
                color: shineGold, fontWeight: FontWeight.w900, fontSize: 22)),
          )),
    ),
  );
}

class HpBar extends StatelessWidget {
  const HpBar({super.key, required this.hp, required this.maxHp, this.height = 16, this.showText = true});
  final int hp, maxHp;
  final double height;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final f = maxHp == 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: f),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final c = v > .5 ? shineJade : (v > .25 ? const Color(0xFFFFB84D) : shineEmber);
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(height),
            border: Border.all(color: Colors.white12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: Stack(children: [
              FractionallySizedBox(
                widthFactor: v.clamp(0.0, 1.0),
                child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.withValues(alpha: .75), c]))),
              ),
              if (showText) Center(child: Text('$hp / $maxHp', style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)]))),
            ]),
          ),
        );
      },
    );
  }
}