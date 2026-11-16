import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Petunjuk navigasi lokal saja. Seluruh data pertandingan tetap di Supabase.
/// Jangan menyimpan token autentikasi atau state gameplay di sini.
class ActiveOnlineRoom {
  const ActiveOnlineRoom({
    required this.roomId,
    required this.roomCode,
    required this.playerId,
  });

  final String roomId;
  final String roomCode;
  final String playerId;

  Map<String, String> toJson() => {
    'room_id': roomId,
    'room_code': roomCode,
    'player_id': playerId,
  };

  static ActiveOnlineRoom? fromJson(Object? data) {
    if (data is! Map) return null;
    final id = data['room_id'];
    final code = data['room_code'];
    final uid = data['player_id'];
    if (id is! String || code is! String || uid is! String ||
        !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id) ||
        !RegExp(r'^[A-F0-9]{6}$').hasMatch(code) || uid.isEmpty) {
      return null;
    }
    return ActiveOnlineRoom(roomId: id, roomCode: code, playerId: uid);
  }

  /// A previous user or a room that has finished must not be auto-resumed.
  bool mayResume(String? currentPlayerId, Map<String, dynamic>? room) {
    if (currentPlayerId == null || playerId != currentPlayerId || room == null) {
      return false;
    }
    if (room['id']?.toString() != roomId) return false;
    if (room['host_id'] != currentPlayerId && room['guest_id'] != currentPlayerId) {
      return false;
    }
    return room['status'] == 'waiting' || room['status'] == 'playing';
  }
}

class ActiveOnlineRoomStore {
  static const key = 'shine_active_online_room_v15';

  static Future<void> save(ActiveOnlineRoom room) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(room.toJson()));
  }

  static Future<ActiveOnlineRoom?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return ActiveOnlineRoom.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }


  /// A stale tab must not erase a different room opened in another tab.
  static Future<void> clearIfRoom(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await read();
    if (current?.roomId == roomId) await prefs.remove(key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
