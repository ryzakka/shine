import 'package:flutter_test/flutter_test.dart';
import 'package:shine/data/characters.dart';
import 'package:shine/domain/battle_match.dart';
import 'package:shine/domain/battle_rules.dart';
import 'package:shine/game/bot_player.dart';
import 'package:shine/game/saved_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocalBattle testBattle() => LocalBattle(
  teamA: ['chaminhyuk','leejunseo','hanseoah'],
  teamB: ['kwontaehyuk','kangjiwoo','choinari'],
);

void main() {
  group('Shine: acuan Jurassic World', () {
    test('PA dasar 1,2,3,4 lalu tetap', () {
      expect([for (int i=1;i<=7;i++) BattleRules.basePoints(i)],
        [1,2,3,4,4,4,4]);
    });
    test('4 bank + 4 PA dasar = 8', () {
      expect(BattleRules.availablePoints(globalTurn: 8,carriedReserve:4),8);
    });
    test('pengali serang dan blok', () {
      final hit = BattleRules.resolveAttack(
        attackPoints: 4,defenderBlockPoints:2,attackStat:30);
      expect(hit.effectiveAttack,2);
      expect(hit.damage,72);
      expect(BattleRules.resolveAttack(
        attackPoints: 4,defenderBlockPoints:4,attackStat:30).damage,0);
      expect(BattleRules.resolveAttack(
        attackPoints: 8,defenderBlockPoints:0,attackStat:30).damage,600);
    });
    test('PA harus dialokasikan semua dan bank dibatasi', () {
      expect(() => BattleRules.validateAllocation(
        available:4,attack:1,defend:1,reserve:1),throwsArgumentError);
      expect(() => BattleRules.validateAllocation(
        available:8,attack:2,defend:1,reserve:5),throwsArgumentError);
    });
  });

  group('Shine: keputusan permainan', () {
    test('katalog lengkap 26 tokoh dengan 1 skill aktif per tokoh', () {
      expect(characters.length,26);
      expect(characters.map((c)=>c.id).toSet().length,26);
      expect(characters.every((c)=>c.skill.isNotEmpty && c.cost>0 && c.cooldown>0),true);
    });
    test('pertahanan hanya sampai giliran lawan berikutnya', () {
      final battle = testBattle();
      battle.act(defend:1); // A T1
      expect(battle.teams[0].block,1);
      battle.act(reserve:2); // B T2, tanpa serang
      expect(battle.teams[0].block,0);
    });
    test('skill ofensif ditahan, bonus berlaku jika serangan lolos', () {
      final battle=testBattle();
      battle.act(reserve:1); // A T1
      battle.act(defend:2); // B T2
      battle.act(attack:2,skill:true); // A T3 (4 PA: 2 attack + 2 skill)
      expect(battle.teams[1].current.hp, battle.teams[1].current.spec.hp);
      expect(battle.teams[0].current.cooldown,2);
    });
    test('CD berkurang saat tokoh menjadi cadangan', () {
      final battle=testBattle();
      battle.act(reserve:1); // A T1
      battle.act(reserve:2); // B T2
      battle.act(attack:2,skill:true); // A T3 cd2
      battle.act(attack:2,reserve:4); // B T4 (6 PA)
      battle.act(swapTo:1); // A T5 -> cd1 untuk Min-hyuk di cadangan
      expect(battle.teams[0].fighters[0].cooldown,1);
      battle.act(attack:4,reserve:4); // B T6 (8 PA)
      battle.act(swapTo:0); // A T7 -> cd0
      expect(battle.teams[0].fighters[0].cooldown,0);
    });
    test('waktu giliran lokal berakhir: skip tanpa serangan', () {
      final battle = testBattle();
      final oldHp = battle.teams[1].current.hp;
      battle.turnDeadlineUtc = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      battle.skipTimedOutTurn();
      expect(battle.turn, 2);
      expect(battle.teams[1].current.hp, oldHp);
      expect(battle.history.last, contains('Waktu Tim A habis'));
      expect(battle.turnDeadlineUtc.isAfter(DateTime.now().toUtc()), true);
    });
    test('aksi terlambat ditolak dan giliran maju', () {
      final battle = testBattle();
      battle.turnDeadlineUtc = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      expect(() => battle.act(attack: 1), throwsStateError);
      expect(battle.turn, 2);
    });
    test('pergantian berdiri sendiri dan tidak menambah PA cadangan', () {
      final battle=testBattle();
      expect(()=>battle.act(swapTo:1,attack:1),throwsStateError);
      battle.act(swapTo:1);
      expect(battle.turn,2);
      expect(battle.teams[0].reserve,0);
    });
    test('poin simpan bisa dibawa ke giliran selanjutnya', () {
      final battle=testBattle();
      battle.act(reserve:1); // A T1
      battle.act(reserve:2); // B T2
      expect(battle.available,4); // T3: 3 dasar + 1 bank
      battle.act(attack:4);
      expect(battle.teams[0].reserve,0);
    });
  });
  group('Shine: alur permainan mandiri', () {
    test('status pertandingan dapat disimpan dan dipulihkan', () {
      final match = testBattle();
      match.act(reserve: 1);
      match.act(reserve: 2);
      final restored = LocalBattle.fromJson(match.toJson());
      expect(restored.turn, 3);
      expect(restored.teams[0].reserve, 1);
      expect(restored.teams[1].reserve, 2);
      expect(restored.history.length, 3);
      expect(restored.encode(), match.encode());
    });
    test('AI tidak memakai poin lebih besar dari yang tersedia', () {
      final match = testBattle();
      final bot = ShineBot(difficulty: 2);
      for (var i = 0; i < 18 && match.winner == null; i++) {
        if (match.acting == 0) {
          final available = match.available;
          match.act(attack: available);
        } else {
          final available = match.available;
          final move = bot.choose(match);
          if (move.swapTo != null) {
            match.act(swapTo: move.swapTo);
          } else {
            final cost = move.skill ? match.teams[1].current.spec.cost : 0;
            expect(move.attack + move.defend + move.reserve + cost, available);
            match.act(attack: move.attack, defend: move.defend,
              reserve: move.reserve, skill: move.skill);
          }
        }
      }
      expect(match.turn, greaterThan(2));
      expect(match.history.length, match.turn);
    });
    test('penyimpanan offline tetap tersedia tanpa Supabase', () async {
      SharedPreferences.setMockInitialValues({});
      final match = testBattle();
      match.act(reserve: 1);
      await LocalGameStorage.save(match, againstBot: true, difficulty: 1);
      final loaded = await LocalGameStorage.load();
      expect(loaded, isNotNull);
      expect(loaded!.battle.turn, 2);
      expect(loaded.againstBot, true);
      await LocalGameStorage.recordResult(againstBot: true, winner: 0);
      expect((await LocalGameStorage.records())['wins'], 1);
      expect(await LocalGameStorage.load(), isNull);
    });
  });
}
