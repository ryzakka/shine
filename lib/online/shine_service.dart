import 'dart:async';
import 'room_revision_tracker.dart';
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

  /// v1.4: penamaan dan privasi diputuskan di server (tidak di query tabel langsung).
  Future<Map<String, dynamic>> createNamedRoom({
    required String playerName, required bool isPublic, String roomTitle = '',
  }) async {
    await ensureSignedIn();
    final result = await client.rpc('shine_create_room_v14', params: {
      'p_visibility': isPublic ? 'public' : 'private',
      'p_room_title': roomTitle.trim(), 'p_player_name': playerName.trim(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> joinNamedRoom({
    required String code, required String playerName,
  }) async {
    await ensureSignedIn();
    final result = await client.rpc('shine_join_named_room_v14', params: {
      'p_code': code.trim().toUpperCase(), 'p_player_name': playerName.trim(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> joinPublicRoom({
    required String roomId, required String playerName,
  }) async {
    await ensureSignedIn();
    final result = await client.rpc('shine_join_public_room_v14', params: {
      'p_room_id': roomId, 'p_player_name': playerName.trim(),
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> publicRooms() async {
    await ensureSignedIn();
    final result = await client.rpc('shine_list_public_rooms');
    return [for (final r in result as List) Map<String, dynamic>.from(r as Map)];
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

  /// Always read the authoritative server state. Supabase Realtime is used
  /// for immediate updates, while polling is a fallback if replication is not
  /// enabled for shine_rooms or a browser misses an event while in background.
  Future<Map<String, dynamic>?> roomById(String id) async {
    final room = await client.from('shine_rooms')
        .select().eq('id', id).maybeSingle();
    return room == null ? null : Map<String, dynamic>.from(room);
  }

  Stream<List<Map<String, dynamic>>> watchRoom(String id) {
    final tracker = RoomRevisionTracker();
    StreamSubscription<List<Map<String, dynamic>>>? realtime;
    Timer? polling;
    bool fetching = false;
    bool disposed = false;
    late final StreamController<List<Map<String, dynamic>>> updates;

    void publish(Map<String, dynamic>? room) {
      if (disposed || updates.isClosed || !tracker.accept(room)) return;
      updates.add(room == null ? <Map<String, dynamic>>[] : [room]);
    }

    Future<void> refresh() async {
      if (fetching || disposed) return;
      fetching = true;
      try {
        publish(await roomById(id));
      } catch (error, stack) {
        // Keep the last good state during a temporary disconnection.
        // On first load let the screen show an actionable error.
        if (!disposed && !updates.isClosed && !tracker.hasSnapshot) {
          updates.addError(error, stack);
        }
      } finally {
        fetching = false;
      }
    }

    updates = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        // Install the independent fallback FIRST, even if Realtime throws.
        unawaited(refresh());
        polling = Timer.periodic(const Duration(seconds: 2), (_) {
          unawaited(refresh());
        });
        try {
          realtime = client.from('shine_rooms')
              .stream(primaryKey: ['id']).eq('id', id)
              .listen((rows) {
            // Empty Realtime snapshots can be transient. Confirm via HTTP.
            if (rows.isNotEmpty) {
              publish(Map<String, dynamic>.from(rows.first));
            } else {
              unawaited(refresh());
            }
          }, onError: (Object _) {
            unawaited(refresh());
          });
        } catch (_) {
          // Polling alone still advances the guest to playing.
        }
      },
      onCancel: () async {
        disposed = true;
        polling?.cancel();
        await realtime?.cancel();
      },
    );
    return updates.stream;
  }

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
