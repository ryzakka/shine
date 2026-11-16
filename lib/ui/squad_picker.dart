import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/characters.dart';
import 'shine_ui.dart';

// ───────────── Pemilih tim ─────────────

class SquadPicker extends StatefulWidget {
  const SquadPicker({super.key, required this.defaults, this.title = 'RAKIT TIM'});
  final List<String> defaults;
  final String title;
  @override
  State<SquadPicker> createState() => _SquadPickerState();
}

class _SquadPickerState extends State<SquadPicker> {
  late final List<String> selected = [...widget.defaults];

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

  void _detail(CharacterSpec c) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true,
    builder: (ctx) => SafeArea(child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .86),
      child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Portrait(c, width: 104, height: 150, radius: 14),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatPill('HP ${c.hp}', icon: Icons.favorite, color: shineJade),
              StatPill('ATK ${c.attack}', icon: Icons.bolt, color: shineEmber),
            ]),
            const SizedBox(height: 14),
            Container(
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
                Wrap(spacing: 6, children: [
                  StatPill('${c.cost} PA', color: shineGold),
                  StatPill('CD ${c.cooldown}', color: shineGold),
                  StatPill(skillKindLabel(c.kind), color: shineViolet),
                ]),
              ]),
            ),
          ])),
        ]),
        const SizedBox(height: 18),
        ShineButton(
            label: selected.contains(c.id) ? 'LEPAS DARI TIM' : 'MASUKKAN KE TIM',
            icon: selected.contains(c.id) ? Icons.remove_circle_outline : Icons.add_circle_outline,
            primary: !selected.contains(c.id),
            onPressed: () { Navigator.pop(ctx); _toggle(c); }),
      ]),
    )))),
  );

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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: shineGold.withValues(alpha: .3), blurRadius: 16, spreadRadius: -4)]),
        child: Stack(fit: StackFit.expand, children: [
          Portrait(c, radius: 14),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: const [.5, 1], colors: [Colors.transparent, Colors.black.withValues(alpha: .85)])))),
          Positioned(left: 6, right: 6, bottom: 5, child: Text(c.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
          Positioned(top: 5, left: 5, child: CircleAvatar(radius: 10,
              backgroundColor: shineGold, child: Text('${i + 1}', style: const TextStyle(
                  color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)))),
          const Positioned(top: 5, right: 5, child: Icon(Icons.cancel, size: 18, color: Colors.white70)),
        ]),
      ),
    );
  }

  Widget _tile(CharacterSpec c) {
    final isSelected = selected.contains(c.id);
    final full = selected.length >= 3;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: !isSelected && full ? .5 : 1,
      child: GestureDetector(
        onTap: () => _toggle(c),
        onLongPress: () => _detail(c),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? shineGold : Colors.white12,
                  width: isSelected ? 2.2 : 1),
              boxShadow: isSelected
                  ? [BoxShadow(color: shineGold.withValues(alpha: .4), blurRadius: 18, spreadRadius: -2)]
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
                    style: const TextStyle(fontSize: 10, color: shineGold, fontWeight: FontWeight.w700)),
              ])),
              if (isSelected) Positioned(top: 7, right: 7, child: CircleAvatar(
                  radius: 13, backgroundColor: shineGold,
                  child: Text('${selected.indexOf(c.id) + 1}', style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _teamSummary() => ShinePanel(
    padding: const EdgeInsets.all(10), radius: 18,
    child: Column(children: [
      SizedBox(height: 118, child: Row(children: [
        for (var i = 0; i < 3; i++) Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4), child: _slot(i))),
      ])),
      const SizedBox(height: 10),
      Text('${selected.length}/3 tokoh • ketuk untuk melepas',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: shineMuted)),
    ]));

  Widget _characterGrid() => GridView.builder(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190, childAspectRatio: .66,
        crossAxisSpacing: 12, mainAxisSpacing: 12),
    itemCount: characters.length,
    itemBuilder: (context, i) => _tile(characters[i]));

  @override
  Widget build(BuildContext context) {
    final remaining = 3 - selected.length;
    return ShineScaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        TextButton(onPressed: selected.isEmpty ? null : () => setState(selected.clear),
            child: const Text('Kosongkan')),
      ]),
      body: SafeArea(child: LayoutBuilder(builder: (context, size) {
        final wide = size.maxWidth >= 800 ||
            (size.maxWidth >= 680 && size.maxHeight < 540);
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(children: [
            Expanded(child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: size.maxWidth < 800 ? 238 : 300, child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SectionLabel('TIM PILIHAN'),
                      _teamSummary(),
                      const SizedBox(height: 14),
                      const Text('Pilih tepat tiga tokoh. Ketuk kartu untuk memilih. '
                          'Tahan kartu untuk melihat skill, biaya PA, dan cooldown.',
                          style: TextStyle(color: shineMuted, fontSize: 12, height: 1.5)),
                    ]))),
                  VerticalDivider(width: 1, color: Colors.white.withValues(alpha: .12)),
                  Expanded(child: _characterGrid()),
                ])
              : Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                      child: _teamSummary()),
                  Expanded(child: _characterGrid()),
                ])),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF14111F),
                  border: Border(top: BorderSide(color: shineGold.withValues(alpha: .2)))),
              child: Center(child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: ShineButton(
                  icon: remaining == 0 ? Icons.check : Icons.person_add_alt,
                  label: remaining == 0 ? 'MULAI DENGAN 3 TOKOH' : 'PILIH $remaining TOKOH LAGI',
                  onPressed: remaining == 0
                      ? () => Navigator.pop(context, List<String>.from(selected)) : null))),
            ),
          ]),
        ));
      })),
    );
  }

}