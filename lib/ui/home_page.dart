import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/characters.dart';
import '../domain/battle_match.dart';
import '../game/saved_game.dart';
import '../online/shine_service.dart';
import 'arena_page.dart';

const shineGold = Color(0xFFEFC483);
const shineMuted = Color(0xFFAAA5BE);

class ShineHomePage extends StatefulWidget {
  const ShineHomePage({super.key});
  @override
  State<ShineHomePage> createState() => _ShineHomePageState();
}

class _ShineHomePageState extends State<ShineHomePage> {
  final code = TextEditingController();
  bool busy = false;
  int difficulty = 1;
  SavedGame? saved;
  Map<String, int> records = const {'wins':0,'losses':0,'games':0};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final game = await LocalGameStorage.load();
    final stats = await LocalGameStorage.records();
    if (mounted) setState(() { saved = game; records = stats; });
  }

  @override
  void dispose() { code.dispose(); super.dispose(); }

  Future<List<String>?> selectSquad(List<String> defaults) => Navigator.push<List<String>>(
    context, MaterialPageRoute(builder: (_) => SquadPicker(defaults: defaults)));

  Future<void> _openLocal(LocalBattle battle,
      {required bool againstBot, required int level}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      LocalArenaPage(battle: battle, againstBot: againstBot, difficulty: level)));
    await _load();
  }

  Future<void> startBot() async {
    final a = await selectSquad(['chaminhyuk','leejunseo','hanseoah']);
    if (a == null || !mounted) return;
    final ids = characters.map((e) => e.id).where((id) => !a.contains(id)).toList()
      ..shuffle(math.Random());
    final b = ids.take(3).toList();
    await LocalGameStorage.remove();
    if (!mounted) return;
    await _openLocal(LocalBattle(teamA: a, teamB: b),
      againstBot: true, level: difficulty);
  }

  Future<void> local() async {
    final a = await selectSquad(['chaminhyuk','leejunseo','hanseoah']);
    if (a == null || !mounted) return;
    final b = await selectSquad(['kwontaehyuk','kangjiwoo','choinari']);
    if (b == null || !mounted) return;
    await LocalGameStorage.remove();
    if (!mounted) return;
    await _openLocal(LocalBattle(teamA: a, teamB: b),
      againstBot: false, level: 1);
  }

  Future<void> _continue() async {
    if (saved == null) return;
    await _openLocal(saved!.battle,
      againstBot: saved!.againstBot, level: saved!.difficulty);
  }

  Future<void> online({required bool joining}) async {
    if (joining && code.text.trim().length != 6) {
      _notify('Masukkan kode ruang enam karakter.');
      return;
    }
    final lineup = await selectSquad(joining
        ? ['kwontaehyuk','kangjiwoo','choinari']
        : ['chaminhyuk','leejunseo','hanseoah']);
    if (lineup == null || !mounted) return;
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final info = joining
        ? await service.joinRoom(code.text, lineup)
        : await service.createRoom(lineup);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => OnlineArenaPage(roomId: info['id'] as String,
            roomCode: info['code'] as String),
      ));
    } catch (error) {
      _notify('Tidak dapat mengakses ruang: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resumeOnline() async {
    setState(() => busy = true);
    try {
      final service = ShineService(Supabase.instance.client);
      final rooms = await service.myRooms();
      if (!mounted) return;
      if (rooms.isEmpty) { _notify('Belum ada ruang aktif yang bisa dilanjutkan.'); return; }
      final room = await showDialog<Map<String,dynamic>>(context: context,
        builder: (context) => SimpleDialog(title: const Text('Ruang daring kamu'), children: [
          for (final r in rooms) SimpleDialogOption(
            onPressed: () => Navigator.pop(context, r),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [const Icon(Icons.sports_esports, color: shineGold),
                const SizedBox(width: 12), Expanded(child: Text('${r['code']} • ${r['status'] == 'playing' ? 'Sedang bermain' : 'Lobi menunggu'}'))])),
          ),
        ]));
      if (room == null || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        OnlineArenaPage(roomId: room['id'] as String, roomCode: room['code'] as String)));
    } catch (error) { _notify('Tidak dapat membaca ruang: $error'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _howToPlay() => showModalBottomSheet<void>(context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CARA BERMAIN SHINE', style: TextStyle(
          color: shineGold, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 15),
        const Text('1. Pilih tiga tokoh. Satu tokoh aktif, dua lainnya cadangan.\n\n'
          '2. Poin Aksi bertambah dari 1 hingga 4 pada giliran-giliran awal, '
          'dan kamu bisa menyimpan maksimal 4 PA.\n\n'
          '3. Alokasikan PA ke Serang, Bertahan, atau Cadangkan. Serangan '
          'dikurangi pertahanan lawan, kemudian dihitung dengan pengali damage.\n\n'
          '4. Gunakan satu skill aktif khas tokoh bila cukup PA dan cooldown siap.\n\n'
          '5. Pergantian tokoh menghabiskan giliran penuh. Cooldown tetap '
          'turun ketika tokoh berada di cadangan.\n\n'
          '6. Tim yang kehilangan seluruh tiga tokohnya kalah.\n\n'
          '7. Di lobi online, pemain kedua menekan Siap, lalu host menekan Mulai. '
          'Waktu setiap giliran ditentukan host (20–60 detik).\n\n'
          '8. Pemain dapat menyerah; host dapat membubarkan ruang. '
          'Tombol Beranda tidak mengakhiri pertandingan online.',
          style: TextStyle(height: 1.45, fontSize: 13)),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pop(context),
          child: const Text('Mulai bermain')),
      ])),
    ));

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(label, style: const TextStyle(color: shineGold,
      fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 11)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SHINE', style: TextStyle(
      letterSpacing: 5, fontWeight: FontWeight.w900, color: shineGold)),
      actions: [IconButton(tooltip: 'Cara bermain', icon: const Icon(Icons.help_outline),
        onPressed: _howToPlay)]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      Container(height: 210, decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF49344E), Color(0xFF191527)]),
        border: Border.all(color: shineGold.withValues(alpha: .5)),
      ), child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(right: 8, top: 8, bottom: 8, child: Row(children: [
          for (final id in ['chaminhyuk','baekseoyeon'])
            Padding(padding: const EdgeInsets.all(3), child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/portraits/$id.webp', fit: BoxFit.cover, width: 92))),
        ])),
        const Positioned(left: 18, top: 26, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SHINE', style: TextStyle(fontSize: 34,
              color: shineGold, letterSpacing: 4, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text('MANHWA CARD BATTLE', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.8)),
            SizedBox(height: 65),
            Text('26 TOKOH • 3 KARTU PER TIM', style: TextStyle(fontSize: 10)),
          ])),
      ])),
      if (saved != null) ...[
        _section('LANJUTKAN'),
        FilledButton.icon(onPressed: busy ? null : _continue,
          icon: const Icon(Icons.play_arrow),
          label: Text('Lanjutkan • giliran ${saved!.battle.turn}')),
      ],
      _section('MAIN SEKARANG'),
      FilledButton.icon(onPressed: busy ? null : startBot,
        icon: const Icon(Icons.smart_toy_outlined),
        label: const Text('MAIN MELAWAN KOMPUTER')),
      const SizedBox(height: 9),
      Row(children: [const Expanded(child: Text('Tingkat kesulitan',
        style: TextStyle(fontSize: 13, color: shineMuted))),
        SegmentedButton<int>(showSelectedIcon: false, segments: const [
          ButtonSegment(value:0,label:Text('Santai')),
          ButtonSegment(value:1,label:Text('Normal')),
          ButtonSegment(value:2,label:Text('Ahli')),
        ], selected: {difficulty}, onSelectionChanged: (v) => setState(() => difficulty=v.first)),
      ]),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: busy ? null : local,
        icon: const Icon(Icons.people_outline),
        label: const Text('Dua pemain • satu perangkat')),
      Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        const Icon(Icons.emoji_events_outlined, size: 16, color: shineGold),
        const SizedBox(width: 7),
        Text('${records['wins']} menang  •  ${records['losses']} kalah  •  ${records['games']} pertandingan vs komputer',
          style: const TextStyle(fontSize: 11, color: shineMuted)),
      ])),
      _section('LOBI ONLINE • BEDA PERANGKAT'),
      OutlinedButton.icon(onPressed: busy ? null : () => online(joining:false),
        icon: const Icon(Icons.add_circle_outline), label: const Text('Buat lobi online 1 vs 1')),
      const SizedBox(height: 10),
      TextField(controller: code, maxLength: 6, textCapitalization: TextCapitalization.characters,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Fa-f0-9]'))],
        decoration: const InputDecoration(labelText: 'Kode ruang teman',
          hintText: 'Contoh: A1B2C3', border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.key))),
      OutlinedButton.icon(onPressed: busy ? null : () => online(joining:true),
        icon: const Icon(Icons.login), label: const Text('Gabung ruang')),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: busy ? null : resumeOnline,
        icon: const Icon(Icons.restore), label: const Text('Lobi saya / lanjutkan pertandingan')),
      if (busy) const Padding(padding: EdgeInsets.all(16), child:
        Center(child: CircularProgressIndicator())),
      const SizedBox(height: 14),
      const Text('Mode komputer dan dua pemain dapat dimainkan tanpa internet. '
        'Lobi online: tamu menekan Siap, host memilih timer dan memulai. '
        'Setelah mulai, tiap giliran dibatasi waktu. Keluar ke beranda tidak membubarkan ruang.',
        style: TextStyle(fontSize: 11, height: 1.5, color: shineMuted)),
      const SizedBox(height: 16),
    ])),
  );
}

/// Layar penuh agar pemilihan tidak terpotong pada ponsel kecil.
class SquadPicker extends StatefulWidget {
  const SquadPicker({super.key, required this.defaults});
  final List<String> defaults;
  @override
  State<SquadPicker> createState() => _SquadPickerState();
}

class _SquadPickerState extends State<SquadPicker> {
  late final List<String> selected = [...widget.defaults];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('PILIH TIM • ${selected.length}/3'),
      actions: [TextButton(onPressed: () => setState(selected.clear),
        child: const Text('Kosongkan'))]),
    body: SafeArea(child: Column(children: [
      Container(padding: const EdgeInsets.all(12), color: const Color(0xFF292231),
        height: 100, child: Row(children: [
          for (var i = 0; i < 3; i++) Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: i < selected.length
              ? InkWell(onTap: () => setState(() => selected.removeAt(i)),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(5),
                      child: Image.asset(characterById(selected[i]).asset,
                        height: 72, width: 43, fit: BoxFit.cover)),
                    const SizedBox(width: 5),
                    Expanded(child: Text(characterById(selected[i]).name,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10))),
                  ]))
              : DecoratedBox(decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(7)),
                  child: const Center(child: Icon(Icons.add, color: Colors.white54))),
          )),
        ])),
      Expanded(child: GridView.builder(padding: const EdgeInsets.all(11),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 155, childAspectRatio: .57,
          crossAxisSpacing: 9, mainAxisSpacing: 12),
        itemCount: characters.length,
        itemBuilder: (context, i) {
          final c = characters[i];
          final isSelected = selected.contains(c.id);
          return InkWell(onTap: () => setState(() {
            if (isSelected) { selected.remove(c.id); }
            else if (selected.length < 3) { selected.add(c.id); }
            else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Satu tim hanya boleh membawa tiga tokoh.'))); }
          }), child: Container(
            decoration: BoxDecoration(color: const Color(0xFF282232),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? shineGold : Colors.white12, width: isSelected ? 2 : 1)),
            child: Column(children: [
              Expanded(child: Stack(fit: StackFit.expand, children: [
                ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  child: Image.asset(c.asset, fit: BoxFit.cover)),
                if (isSelected) Positioned(top: 5, right: 5,
                  child: CircleAvatar(radius: 13, backgroundColor: shineGold,
                    child: Text('${selected.indexOf(c.id)+1}',
                      style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)))),
              ])),
              Padding(padding: const EdgeInsets.all(6), child: Column(children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                Text('HP ${c.hp} • ATK ${c.attack}',
                  style: const TextStyle(fontSize: 10, color: shineMuted)),
                Text(c.skill, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: shineGold)),
              ])),
            ]),
          ));
        })),
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(
          onPressed: selected.length == 3
              ? () => Navigator.pop(context, List<String>.from(selected)) : null,
          icon: const Icon(Icons.check), label: const Text('MULAI DENGAN 3 TOKOH')))),
    ])),
  );
}
