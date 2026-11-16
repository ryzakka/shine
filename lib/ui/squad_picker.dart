import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/characters.dart';
import 'shine_ui.dart';

/// Pemilih tiga tokoh. Dengan [browse] = true halaman ini menjadi koleksi
/// tokoh (hanya melihat statistik dan skill, tanpa memilih tim).
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
  String? _focus;

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

  Widget _skillBox(CharacterSpec c) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: shineViolet.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: shineViolet.withValues(alpha: .4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.auto_awesome, size: 16, color: shineViolet),
        const SizedBox(width: 6),
        Expanded(child: Text(c.skill, style: const TextStyle(
            fontWeight: FontWeight.w800, color: shineViolet))),
      ]),
      const SizedBox(height: 4),
      Text(skillText(c), style: const TextStyle(fontSize: 12, height: 1.4)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        StatPill('${c.cost} PA', color: shineGold),
        StatPill('CD ${c.cooldown}', color: shineGold),
        StatPill(skillKindLabel(c.kind), color: shineViolet),
      ]),
    ]),
  );

  Widget _identity(CharacterSpec c, {double width = 104, double height = 150}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Portrait(c, width: width, height: height, radius: 14),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatPill('HP ${c.hp}', icon: Icons.favorite, color: shineJade),
              StatPill('ATK ${c.attack}', icon: Icons.bolt, color: shineEmber),
            ]),
          ],
        )),
      ]);

  void _detail(CharacterSpec c) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _identity(c),
        const SizedBox(height: 14),
        _skillBox(c),
        const SizedBox(height: 18),
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

  // ───────────── Slot tim ─────────────

  Widget _slot(int i) {
    if (i >= selected.length) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add, color: Colors.white38),
          const SizedBox(height: 2),
          Text('SLOT ${i + 1}', style: const TextStyle(
              fontSize: 10, color: Colors.white38, letterSpacing: 1.5)),
        ]),
      );
    }
    final c = characterById(selected[i]);
    return GestureDetector(
      onTap: () => setState(() => selected.removeAt(i)),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: shineGold.withValues(alpha: .3),
                blurRadius: 16, spreadRadius: -4)]),
        child: Stack(fit: StackFit.expand, children: [
          Portrait(c, radius: 14),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [.5, 1],
                  colors: [Colors.transparent, Colors.black.withValues(alpha: .85)])))),
          Positioned(left: 6, right: 6, bottom: 5, child: Text(c.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
          Positioned(top: 5, left: 5, child: CircleAvatar(radius: 10,
              backgroundColor: shineGold, child: Text('${i + 1}',
                  style: const TextStyle(color: Colors.black, fontSize: 11,
                      fontWeight: FontWeight.w900)))),
          const Positioned(top: 5, right: 5,
              child: Icon(Icons.cancel, size: 18, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _slotsRow(double height) => SizedBox(height: height, child: Row(children: [
    for (var i = 0; i < 3; i++) Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4), child: _slot(i))),
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
        duration: const Duration(milliseconds: 200),
        opacity: !isSelected && full ? .5 : 1,
        child: GestureDetector(
          onTap: () => _tap(c),
          onLongPress: () => _detail(c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isSelected
                        ? shineGold
                        : (focused && _isWide
                        ? shineGold.withValues(alpha: .55) : Colors.white12),
                    width: isSelected ? 2.2 : 1),
                boxShadow: isSelected
                    ? [BoxShadow(color: shineGold.withValues(alpha: .4),
                    blurRadius: 18, spreadRadius: -2)]
                    : null),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                if (isSelected) Positioned(top: 7, right: 7, child: CircleAvatar(
                    radius: 13, backgroundColor: shineGold,
                    child: Text('${selected.indexOf(c.id) + 1}',
                        style: const TextStyle(color: Colors.black, fontSize: 13,
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
          padding: padding ?? const EdgeInsets.fromLTRB(14, 4, 14, 14),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent, childAspectRatio: .66,
              crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: characters.length,
          itemBuilder: (context, i) => _tile(characters[i]));

  Widget _confirmButton(int remaining) => ShineButton(
      icon: remaining == 0 ? Icons.check : Icons.person_add_alt,
      label: remaining == 0 ? 'MULAI DENGAN 3 TOKOH' : 'PILIH $remaining TOKOH LAGI',
      onPressed: remaining == 0
          ? () => Navigator.pop(context, List<String>.from(selected)) : null);

  // ───────────── Tata letak ─────────────

  Widget _narrowBody(int remaining) => Column(children: [
    if (!widget.browse) Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: ShinePanel(padding: const EdgeInsets.all(10), radius: 18,
            child: Column(children: [
              _slotsRow(118),
              const SizedBox(height: 8),
              Text('${selected.length}/3 tokoh • ketuk untuk memilih, tahan untuk melihat skill',
                  style: const TextStyle(fontSize: 11, color: shineMuted)),
            ]))),
    Expanded(child: _grid(maxExtent: 170)),
    if (!widget.browse) Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
          color: const Color(0xFF14111F),
          border: Border(top: BorderSide(color: shineGold.withValues(alpha: .2)))),
      child: _confirmButton(remaining),
    ),
  ]);

  Widget _focusDetail() {
    final id = _focus;
    if (id == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined, color: Colors.white24, size: 40),
          SizedBox(height: 10),
          Text('Arahkan kursor ke tokoh untuk melihat statistik dan skill-nya.',
              textAlign: TextAlign.center,
              style: TextStyle(color: shineMuted, fontSize: 13, height: 1.45)),
        ]),
      );
    }
    final c = characterById(id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(c, width: 118, height: 170),
      const SizedBox(height: 14),
      _skillBox(c),
    ]);
  }

  Widget _wideBody(int remaining) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _grid(
          maxExtent: 190,
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 20))),
      Container(
        width: 390,
        margin: const EdgeInsets.fromLTRB(8, 4, 20, 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF262136), Color(0xFF14111F)]),
          border: Border.all(color: shineGold.withValues(alpha: .22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.browse) ...[
            _slotsRow(150),
            const SizedBox(height: 8),
            Text('${selected.length}/3 tokoh • klik untuk memilih, klik slot untuk melepas',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: shineMuted)),
            const Divider(height: 28, color: Colors.white12),
          ],
          Expanded(child: SingleChildScrollView(child: _focusDetail())),
          if (!widget.browse) ...[
            const SizedBox(height: 12),
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
              child: const Text('Kosongkan')),
      ]),
      body: SafeArea(
          child: _isWide ? _wideBody(remaining) : _narrowBody(remaining)),
    );
  }
}
