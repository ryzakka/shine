import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/characters.dart';
import 'shine_ui.dart';

class SquadPicker extends StatefulWidget {
  const SquadPicker({super.key, this.defaults = const [],
    this.title = 'RAKIT TIM', this.browse = false});
  final List<String> defaults;
  final String title;
  final bool browse;
  @override
  State<SquadPicker> createState() => _SquadPickerState();
}

class _SquadPickerState extends State<SquadPicker> {
  late final List<String> selected =
  widget.browse ? <String>[] : [...widget.defaults];
  String? _focus = characters.first.id;

  bool get _isWide => shineIsWide(MediaQuery.sizeOf(context));

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

  void _tap(CharacterSpec c) {
    setState(() => _focus = c.id);
    if (widget.browse) {
      if (!_isWide) _detail(c);
      return;
    }
    _toggle(c);
  }

  Widget _skillSection(CharacterSpec c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Icon(Icons.auto_awesome, size: 16, color: shineViolet),
        const SizedBox(width: 6),
        Expanded(child: Text(c.skill.toUpperCase(), style: const TextStyle(
            fontWeight: FontWeight.w900, color: shineViolet,
            fontSize: 13, letterSpacing: 1))),
      ]),
      const SizedBox(height: 6),
      Text(skillText(c), style: TextStyle(
          fontSize: 13, height: 1.45, color: Colors.white.withValues(alpha: .85))),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        StatPill('BIAYA ${c.cost} PA', color: shineGold),
        StatPill('COOLDOWN ${c.cooldown}', color: shineGold),
        StatPill(skillKindLabel(c.kind), color: shineViolet),
      ]),
    ],
  );

  Widget _identity(CharacterSpec c, {double width = 104, double height = 150}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Portrait(c, width: width, height: height, radius: 14),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROFIL PETARUNG', style: TextStyle(
                color: shineGold, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 4),
            Text(c.name, style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatPill('HP ${c.hp}', icon: Icons.favorite, color: shineJade),
              StatPill('ATK ${c.attack}', icon: Icons.flash_on, color: shineEmber),
            ]),
          ],
        )),
      ]);

  void _detail(CharacterSpec c) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _identity(c),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Colors.white12),
            ),
            _skillSection(c),
            const SizedBox(height: 20),
            if (widget.browse)
              ShineButton(label: 'TUTUP', primary: false, icon: Icons.close,
                  onPressed: () => Navigator.pop(ctx))
            else
              ShineButton(
                  label: selected.contains(c.id) ? 'LEPAS DARI TIM' : 'MASUKKAN KE TIM',
                  icon: selected.contains(c.id)
                      ? Icons.remove_circle_outline : Icons.add_circle_outline,
                  primary: !selected.contains(c.id),
                  onPressed: () { Navigator.pop(ctx); _toggle(c); }),
          ]),
    )),
  );

  // ───────────── Slot Formasi Terbuka (Tanpa Box Pembungkus) ─────────────

  Widget _slot(int i) {
    final role = i == 0 ? 'UTAMA' : 'CADANGAN ${i}';
    if (i >= selected.length) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .025),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_rounded, color: Colors.white30, size: 22),
          const SizedBox(height: 3),
          Text(role, style: const TextStyle(
              fontSize: 9.5, color: Colors.white38,
              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ]),
      );
    }
    final c = characterById(selected[i]);
    return GestureDetector(
      onTap: () => setState(() => selected.removeAt(i)),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
                color: shineGold.withValues(alpha: .28),
                blurRadius: 14, spreadRadius: -4)]),
        child: Stack(fit: StackFit.expand, children: [
          Portrait(c, radius: 12),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [.45, 1],
                  colors: [Colors.transparent, Colors.black.withValues(alpha: .88)])))),
          Positioned(left: 6, right: 6, bottom: 5, child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(role, style: const TextStyle(
                  fontSize: 8, color: shineGold, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
            ],
          )),
          const Positioned(top: 5, right: 5,
              child: Icon(Icons.cancel, size: 16, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _slotsRow(double height) => SizedBox(height: height, child: Row(children: [
    for (var i = 0; i < 3; i++) Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5), child: _slot(i))),
  ]));

  // ───────────── Kisi tokoh ─────────────

  Widget _tile(CharacterSpec c) {
    final isSelected = selected.contains(c.id);
    final focused = _focus == c.id;
    final full = selected.length >= 3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) { if (_isWide && _focus != c.id) setState(() => _focus = c.id); },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: !isSelected && full ? .42 : 1,
        child: GestureDetector(
          onTap: () => _tap(c),
          onLongPress: () => _detail(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isSelected
                        ? shineGold
                        : (focused && _isWide
                        ? shineGold.withValues(alpha: .5) : Colors.white10),
                    width: isSelected ? 2.0 : 1),
                boxShadow: isSelected
                    ? [BoxShadow(color: shineGold.withValues(alpha: .35),
                    blurRadius: 16, spreadRadius: -2)]
                    : null),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
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
                      style: const TextStyle(fontSize: 10, color: shineGold,
                          fontWeight: FontWeight.w700)),
                ])),
                if (isSelected) Positioned(top: 6, right: 6, child: Container(
                    width: 24, height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: shineGold, shape: BoxShape.circle),
                    child: Text('${selected.indexOf(c.id) + 1}',
                        style: const TextStyle(color: Colors.black, fontSize: 12,
                            fontWeight: FontWeight.w900)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid({required double maxExtent, EdgeInsets? padding}) =>
      GridView.builder(
          padding: padding ?? const EdgeInsets.fromLTRB(16, 6, 16, 16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent, childAspectRatio: .66,
              crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: characters.length,
          itemBuilder: (context, i) => _tile(characters[i]));

  Widget _confirmButton(int remaining) => ShineButton(
      icon: remaining == 0 ? Icons.check_circle_outline : Icons.person_add_alt,
      label: remaining == 0 ? 'KUNCI TIM & MULAI' : 'PILIH $remaining TOKOH LAGI',
      onPressed: remaining == 0
          ? () => Navigator.pop(context, List<String>.from(selected)) : null);

  // ───────────── Tata letak ─────────────

  Widget _narrowBody(int remaining) => Column(children: [
    if (!widget.browse) Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: .07))),
      ),
      child: Column(children: [
        _slotsRow(104),
        const SizedBox(height: 8),
        Text('${selected.length}/3 terpilih • ketuk kartu untuk memilih, tahan untuk info skill',
            style: const TextStyle(fontSize: 11, color: shineMuted)),
      ]),
    ),
    Expanded(child: _grid(maxExtent: 165)),
    if (!widget.browse) Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
          color: const Color(0xE60E0C17),
          border: Border(top: BorderSide(color: shineGold.withValues(alpha: .22)))),
      child: _confirmButton(remaining),
    ),
  ]);

  Widget _focusDetail() {
    final id = _focus ?? characters.first.id;
    final c = characterById(id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(c, width: 112, height: 162),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, color: Colors.white12),
      ),
      _skillSection(c),
    ]);
  }

  Widget _wideBody(int remaining) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _grid(
          maxExtent: 185,
          padding: const EdgeInsets.fromLTRB(24, 6, 16, 24))),
      Container(
        width: 390,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .25),
          border: Border(left: BorderSide(color: Colors.white.withValues(alpha: .08))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.browse) ...[
            const Text('FORMASI TIM (3 TOKOH)', style: TextStyle(
                color: shineGold, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
            const SizedBox(height: 10),
            _slotsRow(132),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1, color: Colors.white12),
            ),
          ],
          Expanded(child: SingleChildScrollView(child: _focusDetail())),
          if (!widget.browse) ...[
            const SizedBox(height: 14),
            _confirmButton(remaining),
          ],
        ]),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final remaining = 3 - selected.length;
    return ShineScaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (!widget.browse)
          TextButton(
              onPressed: selected.isEmpty ? null : () => setState(selected.clear),
              child: const Text('Reset')),
      ]),
      body: SafeArea(
          child: _isWide ? _wideBody(remaining) : _narrowBody(remaining)),
    );
  }
}