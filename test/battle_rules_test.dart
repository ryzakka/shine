import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/battle_rules.dart';
import '../lib/data/character_catalog.dart';

void main() {
  group('Shine: Jurassic World core', () {
    test('PA dasar naik 1, 2, 3, 4 lalu stabil', () {
      expect([for (var t = 1; t <= 6; t++) BattleRules.basePoints(t)],
          [1, 2, 3, 4, 4, 4]);
    });

    test('4 PA yang disimpan menambah PA menjadi 8', () {
      expect(BattleRules.availablePoints(globalTurn: 6, carriedReserve: 4), 8);
    });

    test('alokasi harus tepat dan cadangan maksimum 4', () {
      BattleRules.validateAllocation(
          available: 4, attack: 1, defend: 1, reserve: 2);
      expect(
        () => BattleRules.validateAllocation(
            available: 8, attack: 1, defend: 0, reserve: 7),
        throwsArgumentError,
      );
    });

    test('4 serang melawan 2 bertahan dengan ATK 30 menghasilkan 72', () {
      final result = BattleRules.resolveAttack(
          attackPoints: 4, defenderBlockPoints: 2, attackStat: 30);
      expect(result.effectiveAttack, 2);
      expect(result.multiplier, 2.4);
      expect(result.damage, 72);
    });

    test('8 serang menghasilkan pengali 20x', () {
      expect(
        BattleRules.resolveAttack(
          attackPoints: 8, defenderBlockPoints: 0, attackStat: 30,
        ).damage,
        600,
      );
    });

    test('pertahanan penuh menahan serangan', () {
      expect(
        BattleRules.resolveAttack(
          attackPoints: 3, defenderBlockPoints: 3, attackStat: 30,
        ).damage,
        0,
      );
    });

    test('skill khusus bisa mengabaikan sebagian pertahanan', () {
      final result = BattleRules.resolveAttack(
        attackPoints: 3,
        defenderBlockPoints: 2,
        attackStat: 30,
        piercingBlockPoints: 1,
      );
      expect(result.effectiveAttack, 2);
      expect(result.damage, 72);
    });

    test('cooldown berkurang setiap giliran tim, termasuk saat cadangan', () {
      final afterActivation = BattleRules.cooldownAfterOwnTurn(
          currentCooldown: 0,
          activatedThisTurn: true,
          skillCooldownTurns: 2);
      final afterNextTurn = BattleRules.cooldownAfterOwnTurn(
          currentCooldown: afterActivation,
          activatedThisTurn: false,
          skillCooldownTurns: 2);
      final afterSecondTurn = BattleRules.cooldownAfterOwnTurn(
          currentCooldown: afterNextTurn,
          activatedThisTurn: false,
          skillCooldownTurns: 2);
      expect([afterActivation, afterNextTurn, afterSecondTurn], [2, 1, 0]);
    });

    test('katalog berisi 26 tokoh dengan ID unik', () {
      expect(shineCharacters.length, 26);
      expect(shineCharacters.map((e) => e.id).toSet().length, 26);
    });
  });
}
