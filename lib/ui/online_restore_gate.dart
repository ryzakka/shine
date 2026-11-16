import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../online/active_room_store.dart';
import '../online/shine_service.dart';
import 'arena_page.dart';
import 'home_page.dart';
import 'shine_ui.dart';

/// App entry point: restore a verified online membership before showing the menu.
/// On a temporary network error we keep the recovery hint and allow a retry.
class ShineOnlineRestoreGate extends StatefulWidget {
  const ShineOnlineRestoreGate({super.key});

  @override
  State<ShineOnlineRestoreGate> createState() => _ShineOnlineRestoreGateState();
}

class _ShineOnlineRestoreGateState extends State<ShineOnlineRestoreGate> {
  bool _checking = true;
  bool _skipRestore = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    if (mounted) setState(() { _checking = true; _problem = null; });
    try {
      final saved = await ActiveOnlineRoomStore.read();
      if (saved == null) {
        if (mounted) setState(() => _checking = false);
        return;
      }
      final client = Supabase.instance.client;
      // Never silently create a fresh anonymous user while restoring:
      // that user would not belong to the original room.
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid != saved.playerId) {
        if (mounted) setState(() {
          _checking = false;
          _problem = 'Identitas sesi sebelumnya tidak ditemukan di browser ini. '
              'Gunakan akun/browser asal agar bisa masuk lagi ke ruang yang sama.';
        });
        return;
      }
      final room = await ShineService(client).roomById(saved.roomId);
      if (!mounted || _skipRestore) return;
      if (!saved.mayResume(uid, room)) {
        await ActiveOnlineRoomStore.clear();
        if (mounted) setState(() => _checking = false);
        return;
      }
      setState(() => _checking = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _skipRestore) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OnlineArenaPage(
            roomId: saved.roomId,
            roomCode: saved.roomCode,
          ),
        ));
      });
    } catch (_) {
      if (mounted && !_skipRestore) setState(() {
        _checking = false;
        _problem = 'Belum dapat memeriksa pertandingan online. '
            'Periksa sambungan internet lalu coba lagi; sesi tidak dihapus.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checking && (_problem == null || _skipRestore)) {
      return const ShineHomePage();
    }
    return ShineScaffold(body: SafeArea(child: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_checking) const CircularProgressIndicator(color: shineGold)
          else const Icon(Icons.wifi_find, color: shineGold, size: 42),
          const SizedBox(height: 20),
          Text(_checking ? 'MEMULIHKAN SESI SHINE' : 'BELUM BISA MEMULIHKAN',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
              color: shineGold, letterSpacing: 1.6)),
          const SizedBox(height: 10),
          Text(_checking ? 'Menghubungkan kembali ke ruang dan giliran terakhirmu…'
             : _problem!, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: shineMuted, height: 1.5)),
          if (!_checking) ...[
            const SizedBox(height: 20),
            ShineButton(label: 'COBA LAGI', icon: Icons.refresh,
              onPressed: _restore),
            TextButton(onPressed: () => setState(() => _skipRestore = true),
              child: const Text('KE MENU (SESI TETAP TERSIMPAN)')),
          ],
        ])),
    ))));
  }
}
