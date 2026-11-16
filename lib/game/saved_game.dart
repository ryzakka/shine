import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/battle_match.dart';

class SavedGame {
  const SavedGame({required this.battle, required this.againstBot,
    required this.difficulty});
  final LocalBattle battle;
  final bool againstBot;
  final int difficulty;
}

/// Save data per device: no login or network access required.
class LocalGameStorage {
  static const _saveKey = 'shine_v1_active_game';
  static const _winKey = 'shine_v1_wins';
  static const _lossKey = 'shine_v1_losses';
  static const _gamesKey = 'shine_v1_played';

  static Future<void> save(LocalBattle battle,
      {required bool againstBot, required int difficulty}) async {
    final prefs = await SharedPreferences.getInstance();
    if (battle.winner != null) {
      await prefs.remove(_saveKey);
      return;
    }
    await prefs.setString(_saveKey, jsonEncode({
      'battle': battle.toJson(), 'againstBot': againstBot,
      'difficulty': difficulty,
    }));
  }

  static Future<SavedGame?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_saveKey);
    if (saved == null) return null;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      return SavedGame(
        battle: LocalBattle.fromJson(Map<String, dynamic>.from(data['battle'] as Map)),
        againstBot: data['againstBot'] == true,
        difficulty: (data['difficulty'] as num?)?.toInt() ?? 1,
      );
    } catch (_) {
      await prefs.remove(_saveKey);
      return null;
    }
  }

  static Future<void> recordResult({required bool againstBot,
      required int winner}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saveKey);
    if (!againstBot) return;
    await prefs.setInt(_gamesKey, (prefs.getInt(_gamesKey) ?? 0) + 1);
    final key = winner == 0 ? _winKey : _lossKey;
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  static Future<Map<String, int>> records() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'wins': prefs.getInt(_winKey) ?? 0,
      'losses': prefs.getInt(_lossKey) ?? 0,
      'games': prefs.getInt(_gamesKey) ?? 0,
    };
  }

  static Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saveKey);
  }
}
