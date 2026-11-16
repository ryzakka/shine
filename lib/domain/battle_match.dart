import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/characters.dart';
import 'battle_rules.dart';

class Fighter {
  Fighter(this.spec) : hp = spec.hp;
  final CharacterSpec spec;
  int hp;
  int cooldown = 0;
  bool get alive => hp > 0;
}

class BattleTeam {
  BattleTeam(List<String> ids)
      : fighters = ids.map((id) => Fighter(characterById(id))).toList();
  final List<Fighter> fighters;
  int active = 0;
  int reserve = 0;
  int block = 0;
  Fighter get current => fighters[active];
  bool get defeated => fighters.every((fighter) => !fighter.alive);
}

/// Prototipe lokal hotseat. Multiplayer menggunakan RPC PostgreSQL sebagai
/// sumber kebenaran terpisah; klien tidak boleh menentukan hasil laga daring.
class LocalBattle extends ChangeNotifier {
  LocalBattle({required List<String> teamA, required List<String> teamB})
      : teams = [BattleTeam(teamA), BattleTeam(teamB)] {
    if (teamA.length != 3 || teamB.length != 3 ||
        teamA.toSet().length != 3 || teamB.toSet().length != 3) {
      throw ArgumentError('Setiap tim harus memilih 3 tokoh berbeda.');
    }
  }

  final List<BattleTeam> teams;
  final List<String> history = ['Pertarungan dimulai!'];
  int turn = 1;
  int? winner;
  DateTime turnDeadlineUtc = DateTime.now().toUtc().add(const Duration(seconds: 30));
  String log = 'Pertarungan dimulai!';
  int get acting => (turn - 1) % 2;
  Map<String, dynamic> toJson() => {
    'turn': turn, 'winner': winner, 'log': log, 'history': history,
    'turn_deadline': turnDeadlineUtc.toIso8601String(),
    'teams': [for (final t in teams) {
      'active': t.active, 'reserve': t.reserve, 'block': t.block,
      'cards': [for (final f in t.fighters) {
        'id': f.spec.id, 'hp': f.hp, 'cd': f.cooldown,
      }],
    }],
  };

  String encode() => jsonEncode(toJson());

  factory LocalBattle.fromJson(Map<String, dynamic> state) {
    final teamsRaw = (state['teams'] as List);
    final a = (teamsRaw[0] as Map)['cards'] as List;
    final b = (teamsRaw[1] as Map)['cards'] as List;
    final match = LocalBattle(
      teamA: a.map((e) => (e as Map)['id'] as String).toList(),
      teamB: b.map((e) => (e as Map)['id'] as String).toList(),
    );
    final t = (state['turn'] as num).toInt();
    if (t < 1 || t > 10000) throw const FormatException('Giliran rusak');
    match.turn = t;
    match.turnDeadlineUtc = DateTime.tryParse(state['turn_deadline'] as String? ?? '')?.toUtc()
        ?? DateTime.now().toUtc().add(const Duration(seconds: 30));
    match.winner = (state['winner'] as num?)?.toInt();
    match.log = state['log'] as String? ?? 'Pertandingan dipulihkan';
    match.history.clear();
    match.history.addAll((state['history'] as List? ?? [match.log]).map((e) => e.toString()));
    for (var side = 0; side < 2; side++) {
      final raw = teamsRaw[side] as Map;
      final team = match.teams[side];
      team.active = (raw['active'] as num).toInt();
      team.reserve = (raw['reserve'] as num).toInt();
      team.block = (raw['block'] as num).toInt();
      if (team.active < 0 || team.active > 2 || team.reserve < 0 || team.reserve > 4 || team.block < 0 || team.block > 8) {
        throw const FormatException('Status tim rusak');
      }
      for (var i = 0; i < 3; i++) {
        final stored = (raw['cards'] as List)[i] as Map;
        team.fighters[i].hp = (stored['hp'] as num).toInt();
        team.fighters[i].cooldown = (stored['cd'] as num).toInt();
        if (team.fighters[i].hp < 0 || team.fighters[i].hp > team.fighters[i].spec.hp || team.fighters[i].cooldown < 0) {
          throw const FormatException('Status tokoh rusak');
        }
      }
    }
    return match;
  }

  int get available => BattleRules.availablePoints(
        globalTurn: turn, carriedReserve: teams[acting].reserve);

  /// Mengakhiri giliran dengan aksi, atau pergantian sebagai aksi tunggal.
  void act({
    int attack = 0,
    int defend = 0,
    int reserve = 0,
    bool skill = false,
    int? swapTo,
  }) {
    if (winner != null) throw StateError('Pertandingan sudah berakhir.');
    if (!DateTime.now().toUtc().isBefore(turnDeadlineUtc)) {
      skipTimedOutTurn();
      throw StateError('Waktu habis, giliran telah dilewati.');
    }
    final own = teams[acting];
    final enemy = teams[1 - acting];
    if (swapTo != null) {
      if (attack != 0 || defend != 0 || reserve != 0 || skill) {
        throw StateError('Pergantian adalah satu-satunya tindakan giliran.');
      }
      if (swapTo < 0 || swapTo >= 3 || swapTo == own.active ||
          !own.fighters[swapTo].alive) {
        throw StateError('Tokoh tujuan pergantian tidak valid.');
      }
      own.active = swapTo;
      // Cadangan lama dipertahankan; PA dasar giliran swap tidak tersimpan.
      own.block = 0;
      enemy.block = 0; // Pertahanan lawan hangus sesudah giliran ini.
      log = 'Tim ${acting == 0 ? 'A' : 'B'} mengganti ke ${own.current.spec.name}. Giliran selesai.';
      _tickCooldowns(own);
      turn++;
      _startNextTurn();
      history.add(log);
      notifyListeners();
      return;
    }

    final fighter = own.current;
    final spec = fighter.spec;
    final cost = skill ? spec.cost : 0;
    if (skill && fighter.cooldown != 0) {
      throw StateError('Skill masih cooldown ${fighter.cooldown} giliran tim.');
    }
    BattleRules.validateAllocation(
      available: available,
      attack: attack,
      defend: defend,
      reserve: reserve,
      skillCost: cost,
    );
    if (skill && <String>{'damage', 'pierce', 'recoil',
      'conditional_damage', 'hybrid'}.contains(spec.kind) && attack == 0) {
      throw StateError('Skill ofensif membutuhkan setidaknya 1 PA serang.');
    }
    if (skill && spec.kind == 'conditional_damage' && spec.aux > 0 && attack < spec.aux) {
      throw StateError('Skill ini membutuhkan minimal ${spec.aux} PA serang.');
    }

    var piercing = 0;
    var bonus = 0;
    var bonusBlock = 0;
    var bonusReserve = 0;
    var detail = '';
    if (skill) {
      detail = ' Skill ${spec.skill} aktif.';
      if (spec.kind == 'damage' || spec.kind == 'recoil') {
        bonus = spec.value;
      } else if (spec.kind == 'conditional_damage') {
        if (spec.aux > 0 || enemy.block == 0) bonus = spec.value;
      } else if (spec.kind == 'pierce') {
        piercing = spec.value;
      } else if (spec.kind == 'heal') {
        fighter.hp = math.min(spec.hp, fighter.hp + spec.value);
      } else if (spec.kind == 'heal_all') {
        for (final member in own.fighters) {
          if (member.alive) {
            member.hp = math.min(member.spec.hp, member.hp + spec.value);
          }
        }
      } else if (spec.kind == 'shield') {
        bonusBlock = spec.value;
      } else if (spec.kind == 'reserve') {
        bonusReserve = spec.value;
      } else if (spec.kind == 'drain') {
        enemy.reserve = math.max(0, enemy.reserve - spec.value);
      } else if (spec.kind == 'hybrid') {
        bonus = spec.value;
        bonusBlock = spec.aux;
      } else {
        throw StateError('Jenis skill tidak dikenal.');
      }
    }
    final absorbed = enemy.block;
    final result = BattleRules.resolveAttack(
      attackPoints: attack,
      defenderBlockPoints: absorbed,
      attackStat: spec.attack,
      piercingBlockPoints: piercing,
      bonusDamageOnHit: bonus,
    );
    enemy.current.hp = math.max(0, enemy.current.hp - result.damage);
    if (skill && spec.kind == 'recoil') {
      fighter.hp = math.max(0, fighter.hp - spec.aux);
    }
    own.block = math.min(8, defend + bonusBlock);
    own.reserve = math.min(4, reserve + bonusReserve);
    enemy.block = 0;
    _tickCooldowns(own, activated: skill ? own.active : null);
    log = 'Tim ${acting == 0 ? 'A' : 'B'}: $attack serang, $defend bertahan, '
        '$reserve cadangan. Damage ${result.damage}.' '$detail';
    _autoSubstitute(enemy);
    _autoSubstitute(own);
    if (enemy.defeated) winner = acting;
    if (own.defeated) winner = 1 - acting;
    turn++;
    _startNextTurn();
    history.add(log);
    notifyListeners();
  }

  /// Jika timer habis: lewati satu giliran tanpa serangan.
  /// PA dasar giliran ini hangus, PA cadangan lama tetap tersimpan.
  void skipTimedOutTurn() {
    if (winner != null) return;
    if (DateTime.now().toUtc().isBefore(turnDeadlineUtc)) return;
    final own = teams[acting];
    final enemy = teams[1-acting];
    log = 'Waktu Tim ${acting == 0 ? 'A' : 'B'} habis. Giliran dilewati.';
    own.block = 0;
    enemy.block = 0;
    _tickCooldowns(own);
    turn++;
    _startNextTurn();
    history.add(log);
    notifyListeners();
  }

  void _startNextTurn() {
    turnDeadlineUtc = DateTime.now().toUtc().add(const Duration(seconds: 30));
  }

  void _autoSubstitute(BattleTeam team) {
    if (team.current.alive || team.defeated) return;
    // Aturan pengganti saat KO masih bersifat prototipe; otomatis index terkecil.
    team.active = team.fighters.indexWhere((member) => member.alive);
  }

  void _tickCooldowns(BattleTeam team, {int? activated}) {
    for (var index = 0; index < team.fighters.length; index++) {
      final fighter = team.fighters[index];
      fighter.cooldown = BattleRules.cooldownAfterOwnTurn(
        currentCooldown: fighter.cooldown,
        activatedThisTurn: index == activated,
        skillCooldownTurns: fighter.spec.cooldown,
      );
    }
  }
}
