import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../online/shine_service.dart';
import '../online/active_room_store.dart';
import 'arena_page.dart';
import 'shine_ui.dart';

/// Public directory exposes only explicitly public, empty lobbies.
/// Private rooms remain accessible via invitation code, never via the listing.
class OnlineRoomsPage extends StatefulWidget {
  const OnlineRoomsPage({super.key});
  @override
  State<OnlineRoomsPage> createState() => _OnlineRoomsPageState();
}

class _OnlineRoomsPageState extends State<OnlineRoomsPage> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _title = TextEditingController();
  late final ShineService _service = ShineService(Supabase.instance.client);
  Timer? _refreshTimer;
  bool _busy = false, _refreshing = false, _hasFetched = false;
  bool _publicRoom = true;
  List<Map<String, dynamic>> _rooms = [];
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _init();
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _name.text = prefs.getString('shine_player_name') ?? '';
    await _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _name.dispose(); _code.dispose(); _title.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rooms = await _service.publicRooms();
      if (mounted) setState(() { _rooms = rooms; _directoryError = null; _hasFetched = true; });
    } catch (e) {
      if (mounted) setState(() { _directoryError = 'Daftar ruang belum bisa dimuat: $e'; _hasFetched = true; });
    } finally { _refreshing = false; }
  }

  String? _nameIssue() {
    final n = _name.text.trim();
    if (n.length < 2 || n.length > 24) return 'Nama pemain harus 2–24 karakter.';
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(n)) return 'Nama mengandung karakter tidak valid.';
    return null;
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Save the room before navigation, so a browser refresh can restore it.
  Future<void> _openRoom(Map<String, dynamic> room) async {
    final playerId = _service.client.auth.currentUser?.id;
    if (playerId == null) throw StateError('Sesi pemain belum siap.');
    final id = room['id']?.toString();
    final code = room['code']?.toString();
    if (id == null || code == null) throw StateError('Data ruang tidak lengkap.');
    await ActiveOnlineRoomStore.save(ActiveOnlineRoom(
      roomId: id, roomCode: code, playerId: playerId));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlineArenaPage(roomId: id, roomCode: code)));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() operation) async {
    if (_busy) return;
    final issue = _nameIssue();
    if (issue != null) { _notice(issue); return; }
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shine_player_name', _name.text.trim());
      final room = await operation();
      if (!mounted) return;
      await _openRoom(room);
      if (mounted) await _refresh();
    } catch (e) {
      _notice('Gagal membuka ruang: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rooms = await _service.myRooms();
      if (!mounted) return;
      if (rooms.isEmpty) { _notice('Belum ada pertandingan yang bisa dilanjutkan.'); return; }
      final selected = await showDialog<Map<String, dynamic>>(context: context,
        builder: (context) => SimpleDialog(title: const Text('RUANG SAYA'), children: [
          for (final room in rooms) SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(room),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('${room['code']}   •   ${room['status']}',
                style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        ]));
      if (selected != null && mounted) {
        await _openRoom(selected);
      }
    } catch (e) { _notice('Tidak dapat memuat ruang: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _heading(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, color: shineGold, size: 22), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 15)),
        Text(subtitle, style: const TextStyle(color: shineMuted, height: 1.35, fontSize: 12)),
      ])),
    ]),
  );

  Widget _identity() => ShinePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('IDENTITAS PEMAIN', 'Nama ini terlihat di lobi dan arena, bukan nama tokoh kartu.', Icons.badge_outlined),
    TextField(controller: _name, maxLength: 24,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'))],
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Nama pemain', hintText: 'Misalnya: Zaka',
        prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder(),
        counterText: ''),
    ),
  ]));

  Widget _creation() => ShinePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('BUAT RUANG', 'Dua pemain bergabung, baru kemudian memilih kartu bersama.', Icons.add_circle_outline),
    Wrap(spacing: 8, runSpacing: 8, children: [
      ChoiceChip(label: const Text('PUBLIK'), avatar: const Icon(Icons.public, size: 18),
        selected: _publicRoom, onSelected: _busy ? null : (_) => setState(() => _publicRoom = true)),
      ChoiceChip(label: const Text('PRIVAT'), avatar: const Icon(Icons.lock_outline, size: 18),
        selected: !_publicRoom, onSelected: _busy ? null : (_) => setState(() => _publicRoom = false)),
    ]),
    const SizedBox(height: 10),
    Text(_publicRoom
      ? 'Ruang tampil di daftar publik dan dapat dimasuki siapa saja selama kosong.'
      : 'Ruang tersembunyi dari daftar publik dan hanya dapat dimasuki lewat kode.',
      style: const TextStyle(fontSize: 12, color: shineMuted, height: 1.4)),
    const SizedBox(height: 12),
    TextField(controller: _title, maxLength: 36,
      decoration: const InputDecoration(labelText: 'Judul ruang (opsional)',
        prefixIcon: Icon(Icons.edit_outlined), border: OutlineInputBorder(),
        hintText: 'Arena santai', counterText: '')),
    const SizedBox(height: 10),
    ShineButton(label: 'BUAT ${_publicRoom ? 'RUANG PUBLIK' : 'RUANG PRIVAT'}',
      icon: _publicRoom ? Icons.public : Icons.lock_outline,
      onPressed: _busy ? null : () => _run(() => _service.createNamedRoom(
        playerName: _name.text.trim(), isPublic: _publicRoom,
        roomTitle: _title.text.trim())),
    ),
  ]));

  Widget _privateJoin() => ShinePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('MASUK DENGAN KODE', 'Gunakan kode enam karakter dari pemilik ruang privat.', Icons.key_outlined),
    Row(children: [
      Expanded(child: TextField(controller: _code, maxLength: 6,
        textAlign: TextAlign.center, textCapitalization: TextCapitalization.characters,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Fa-f0-9]'))],
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        decoration: const InputDecoration(border: OutlineInputBorder(),
          hintText: 'A1B2C3', counterText: ''))),
      const SizedBox(width: 10),
      SizedBox(width: 112, child: ShineButton(label: 'GABUNG', height: 56,
        onPressed: _busy ? null : () {
          if (_code.text.trim().length != 6) {
            _notice('Kode ruang harus 6 karakter.'); return;
          }
          _run(() => _service.joinNamedRoom(
            code: _code.text.trim(), playerName: _name.text.trim()));
        })),
    ]),
  ]));

  Widget _publicDirectory() => ShinePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      Expanded(child: _heading('DAFTAR RUANG PUBLIK',
          'Ruang terbuka • 1 dari 2 pemain • diperbarui berkala', Icons.public)),
      IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh),
        tooltip: 'Perbarui daftar'),
    ]),
    if (_directoryError != null) Padding(padding: const EdgeInsets.only(bottom: 10),
      child: Text(_directoryError!, style: const TextStyle(color: shineEmber, fontSize: 12))),
    if (!_hasFetched) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: CircularProgressIndicator()))
    else if (_rooms.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: Text('Belum ada ruang publik yang menunggu pemain.\nBuat ruang publik untuk memulai!',
        textAlign: TextAlign.center, style: TextStyle(color: shineMuted, height: 1.6))))
    else for (final room in _rooms) Padding(padding: const EdgeInsets.only(bottom: 8),
      child: Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF262032), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12)),
        child: Row(children: [
          const Icon(Icons.sports_esports_outlined, size: 28, color: shineGold),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(room['room_title']?.toString() ?? 'Arena publik', maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('Host: ${room['host_name'] ?? 'Pemain'}   •   ${room['turn_seconds'] ?? 30} dtk/giliran',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: shineMuted, fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _busy ? null : () => _run(() => _service.joinPublicRoom(
            roomId: room['room_id'].toString(), playerName: _name.text.trim())),
            child: const Text('MASUK')),
        ])),
    ),
  ]));

  @override
  Widget build(BuildContext context) => ShineScaffold(
    appBar: AppBar(title: const Text('ARENA ONLINE')),
    body: SafeArea(child: Stack(children: [
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1060),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _identity(), const SizedBox(height: 16),
              if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [
                  _creation(), const SizedBox(height: 16), _privateJoin(),
                ])),
                const SizedBox(width: 16),
                Expanded(child: _publicDirectory()),
              ]) else ...[
                _creation(), const SizedBox(height: 16),
                _publicDirectory(), const SizedBox(height: 16), _privateJoin(),
              ],
              const SizedBox(height: 18),
              TextButton.icon(onPressed: _busy ? null : _resume,
                icon: const Icon(Icons.restore), label: const Text('LANJUTKAN RUANG SAYA')),
              const SizedBox(height: 10),
              const Center(child: Text('SHINE  •  v1.5.0',
                style: TextStyle(color: shineMuted, fontSize: 11, letterSpacing: 2))),
            ]))),
        ]);
      }),
      if (_busy) const Positioned.fill(child: IgnorePointer(child: Center(
        child: CircularProgressIndicator()))),
    ])),
  );
}
