import 'package:supabase_flutter/supabase_flutter.dart';

/// Publishable project credentials, NOT an admin/service_role credential.
/// Always rely on RLS and secured PostgreSQL RPC for gameplay integrity.
class ShineSupabaseConfig {
  static const url = 'https://kluryjachdmtslnnqmdk.supabase.co';
  static const publishableKey = 'sb_publishable_7UJsrkXhE67jPXucN8f5uA_iXeUklIs';
}

class ShineService {
  ShineService(this.client);
  final SupabaseClient client;

  Future<void> ensureSignedIn() async {
    if (client.auth.currentUser != null) return;
    await client.auth.signInAnonymously();
  }

  Future<Map<String, dynamic>> createRoom(List<String> cards) async {
    await ensureSignedIn();
    final result = await client.rpc('shine_create_room', params: {
      'p_cards': cards,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> joinRoom(String code, List<String> cards) async {
    await ensureSignedIn();
    final result = await client.rpc('shine_join_room', params: {
      'p_code': code.trim().toUpperCase(),
      'p_cards': cards,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> myRooms() async {
    await ensureSignedIn();
    final result = await client.from('shine_rooms')
      .select('id,code,status,created_at,guest_ready,turn_seconds')
      .inFilter('status', ['waiting','playing'])
      .order('created_at', ascending: false)
      .limit(15);
    return [for (final room in result) Map<String, dynamic>.from(room)];
  }

  Stream<List<Map<String, dynamic>>> watchRoom(String id) => client
      .from('shine_rooms')
      .stream(primaryKey: ['id'])
      .eq('id', id);

  /// Kartu dipilih SETELAH kedua akun bergabung ke ruang.
  Future<void> submitLineup(String roomId, List<String> cards) async {
    await client.rpc('shine_submit_lineup', params: {
      'p_room_id': roomId, 'p_cards': cards,
    });
  }

  Future<void> setReady(String roomId, bool ready) async {
    await client.rpc('shine_set_ready', params: {
      'p_room_id': roomId, 'p_ready': ready,
    });
  }

  Future<void> setTimer(String roomId, int seconds) async {
    await client.rpc('shine_set_timer', params: {
      'p_room_id': roomId, 'p_seconds': seconds,
    });
  }

  Future<void> startRoom(String roomId) async {
    await client.rpc('shine_start_room', params: {'p_room_id': roomId});
  }

  Future<void> leaveLobby(String roomId) async {
    await client.rpc('shine_leave_lobby', params: {'p_room_id': roomId});
  }

  Future<void> endRoom(String roomId, {required bool disband}) async {
    await client.rpc('shine_end_room', params: {
      'p_room_id': roomId, 'p_mode': disband ? 'disband' : 'surrender',
    });
  }

  Future<void> expireTurn(String roomId) async {
    await client.rpc('shine_expire_turn', params: {'p_room_id': roomId});
  }

  Future<void> submit({
    required String id,
    required int revision,
    int attack = 0,
    int defend = 0,
    int reserve = 0,
    bool useSkill = false,
    int? swapTo,
  }) async {
    await client.rpc('shine_submit_action', params: {
      'p_room_id': id,
      'p_expected_revision': revision,
      'p_attack': attack,
      'p_defend': defend,
      'p_reserve': reserve,
      'p_use_skill': useSkill,
      'p_swap_to': swapTo,
    });
  }
}
