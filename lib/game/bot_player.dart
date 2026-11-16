import 'dart:math' as math;
import '../domain/battle_match.dart';
import '../domain/battle_rules.dart';

/// Lawan komputer bermain dengan aturan aksi yang sama dengan pemain.
/// Tidak mengakses database dan tidak dapat mengubah pertandingan daring.
class BotMove {
  const BotMove({this.attack = 0, this.defend = 0, this.reserve = 0,
    this.skill = false, this.swapTo});
  final int attack, defend, reserve;
  final bool skill;
  final int? swapTo;
}

class ShineBot {
  ShineBot({this.difficulty = 1, math.Random? random}) : _rng = random ?? math.Random();
  /// 0 = santai, 1 = normal, 2 = ahli.
  final int difficulty;
  final math.Random _rng;

  BotMove choose(LocalBattle battle) {
    final team = battle.teams[battle.acting];
    final opponent = battle.teams[1 - battle.acting];
    final unit = team.current;
    final spec = unit.spec;
    final points = battle.available;
    final enemy = opponent.current;
    final allowSkill = unit.cooldown == 0;

    BotMove best = BotMove(reserve: math.min(4, points),
      defend: math.max(0, points - math.min(4, points)));
    double bestScore = -1e9;
    for (final useSkill in [false, if (allowSkill) true]) {
      final cost = useSkill ? spec.cost : 0;
      if (cost > points) continue;
      for (var reserve = 0; reserve <= math.min(4, points - cost); reserve++) {
        for (var defend = 0; defend <= points - reserve - cost; defend++) {
          final attack = points - reserve - defend - cost;
          if (useSkill && const {'damage','pierce','recoil','conditional_damage','hybrid'}
              .contains(spec.kind) && attack == 0) continue;
          if (useSkill && spec.kind == 'conditional_damage' && spec.aux > 0 && attack < spec.aux) continue;

          final pierce = useSkill && spec.kind == 'pierce' ? spec.value : 0;
          final bonus = useSkill && const {'damage','recoil','hybrid','conditional_damage'}
              .contains(spec.kind) ? spec.value : 0;
          final hit = BattleRules.resolveAttack(attackPoints: attack,
              defenderBlockPoints: opponent.block, attackStat: spec.attack,
              piercingBlockPoints: pierce, bonusDamageOnHit: bonus);
          final actualDamage = math.min(hit.damage, enemy.hp);
          var score = actualDamage / 8.0 +
              reserve * (battle.turn <= 4 ? 10.0 : 6.0) +
              defend * (enemy.spec.attack > 27 ? 5.7 : 4.7);
          // Pertahanan berlebih lebih kecil nilainya.
          if (defend > 4) score -= (defend - 4) * 3;
          if (enemy.hp <= actualDamage && actualDamage > 0) score += 120;
          if (useSkill) {
            if (spec.kind == 'heal') {
              score += math.min(spec.value, spec.hp - unit.hp) / 3.0;
            } else if (spec.kind == 'heal_all') {
              score += team.fighters.where((e) => e.alive)
                  .map((e) => math.min(spec.value, e.spec.hp - e.hp) / 3.0)
                  .fold<double>(0, (a, b) => a + b);
            } else if (spec.kind == 'shield') {
              score += spec.value * 4.0;
            } else if (spec.kind == 'reserve') {
              score += spec.value * 3.5;
            } else if (spec.kind == 'drain') {
              score += math.min(opponent.reserve, spec.value) * 6.0;
            } else if (spec.kind == 'recoil') {
              score -= spec.aux / 6.0;
            }
            score -= spec.cooldown * 1.5;
          }
          if (difficulty == 0) score += _rng.nextDouble() * 45;
          if (difficulty == 1) score += _rng.nextDouble() * 15;
          if (difficulty == 2) score += _rng.nextDouble() * 3;
          if (score > bestScore) {
            bestScore = score;
            best = BotMove(attack: attack, defend: defend,
                reserve: reserve, skill: useSkill);
          }
        }
      }
    }
    // Pergantian menghabiskan satu giliran penuh; hanya gunakan bila tokoh terancam.
    final backup = <int>[for (var i = 0; i < 3; i++)
      if (i != team.active && team.fighters[i].alive) i];
    if (backup.isNotEmpty && unit.hp / spec.hp < (difficulty == 2 ? .18 : .28) &&
        bestScore < 120) {
      backup.sort((a,b) => team.fighters[b].hp.compareTo(team.fighters[a].hp));
      if (_rng.nextDouble() < (difficulty == 0 ? .4 : .75)) {
        return BotMove(swapTo: backup.first);
      }
    }
    return best;
  }
}
