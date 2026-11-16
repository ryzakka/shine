/// Shine — aturan inti pertempuran yang mengacu pada Jurassic World: The Game.
///
/// Kode ini tidak melakukan validasi otorisasi multiplayer. Pada versi daring,
/// semua keputusan penting wajib diverifikasi oleh backend (Supabase).
import 'dart:math' as math;

class BattleRules {
  BattleRules._();

  static const int maxBasePoints = 4;
  static const int maxReservePoints = 4;
  static const int maxTotalPoints = 8;

  /// Pengali serang untuk 0 s.d. 8 PA serang yang lolos pertahanan.
  static const List<double> attackMultipliers = [
    0, 1, 2.4, 4.2, 6.4, 9, 12, 15.4, 20,
  ];

  /// `globalTurn` dimulai dari 1 dan naik setiap kali giliran berganti tim.
  /// Urutan PA dasar: 1, 2, 3, 4, 4, 4, ...
  static int basePoints(int globalTurn) {
    if (globalTurn < 1) {
      throw ArgumentError.value(globalTurn, 'globalTurn', 'Minimal 1');
    }
    return math.min(globalTurn, maxBasePoints);
  }

  /// PA tersedia = PA dasar + PA cadangan yang dibawa dari giliran tim lalu.
  static int availablePoints({
    required int globalTurn,
    required int carriedReserve,
  }) {
    if (carriedReserve < 0 || carriedReserve > maxReservePoints) {
      throw ArgumentError.value(
        carriedReserve,
        'carriedReserve',
        'Harus 0 sampai $maxReservePoints',
      );
    }
    return math.min(
      maxTotalPoints,
      basePoints(globalTurn) + carriedReserve,
    );
  }

  /// Satu alokasi normal: serang + pertahanan + cadangan + biaya skill.
  /// PA harus dialokasikan seluruhnya, sesuai mekanisme acuan.
  static void validateAllocation({
    required int available,
    required int attack,
    required int defend,
    required int reserve,
    int skillCost = 0,
  }) {
    if (available < 1 || available > maxTotalPoints) {
      throw ArgumentError.value(available, 'available');
    }
    if ([attack, defend, reserve, skillCost].any((n) => n < 0)) {
      throw ArgumentError('Alokasi PA tidak boleh negatif');
    }
    if (reserve > maxReservePoints) {
      throw ArgumentError('Cadangan maksimal $maxReservePoints PA');
    }
    if (attack + defend + reserve + skillCost != available) {
      throw ArgumentError('Seluruh PA harus dialokasikan tepat sekali');
    }
  }

  /// Damage dasar, tanpa bonus kelas karena Shine belum menetapkan kelas.
  /// `piercingBlockPoints` hanya untuk skill khusus yang secara eksplisit
  /// mengabaikan pertahanan; default semua serangan terpengaruh pertahanan.
  /// Pembulatan ke atas adalah konvensi awal dari wiki komunitas, belum final.
  static AttackResult resolveAttack({
    required int attackPoints,
    required int defenderBlockPoints,
    required int attackStat,
    int piercingBlockPoints = 0,
    int bonusDamageOnHit = 0,
  }) {
    if (attackPoints < 0 || attackPoints > maxTotalPoints ||
        defenderBlockPoints < 0 || defenderBlockPoints > maxTotalPoints ||
        attackStat < 0 || piercingBlockPoints < 0 ||
        bonusDamageOnHit < 0) {
      throw ArgumentError('Parameter serangan tidak valid');
    }
    final effectiveBlock = math.max(0, defenderBlockPoints - piercingBlockPoints);
    final effectiveAttack = math.max(0, attackPoints - effectiveBlock);
    final absorbedPoints = math.min(attackPoints, effectiveBlock);
    final multiplier = attackMultipliers[effectiveAttack];
    final damage = (attackStat * multiplier).ceil() +
        (effectiveAttack > 0 ? bonusDamageOnHit : 0);
    return AttackResult(
      effectiveAttack: effectiveAttack,
      absorbedAttackPoints: absorbedPoints,
      multiplier: multiplier,
      damage: damage,
    );
  }

  /// Dipanggil DI AKHIR setiap giliran tim pemilik tokoh, baik tokoh aktif
  /// maupun di cadangan. CD=2: pakai pada T1 -> T2/CD1 -> T3/CD0 -> T4 siap.
  static int cooldownAfterOwnTurn({
    required int currentCooldown,
    required bool activatedThisTurn,
    required int skillCooldownTurns,
  }) {
    if (currentCooldown < 0 || skillCooldownTurns < 0) {
      throw ArgumentError('Cooldown tidak boleh negatif');
    }
    if (activatedThisTurn) {
      if (currentCooldown > 0) {
        throw StateError('Skill masih cooldown');
      }
      return skillCooldownTurns;
    }
    return math.max(0, currentCooldown - 1);
  }
}

class AttackResult {
  const AttackResult({
    required this.effectiveAttack,
    required this.absorbedAttackPoints,
    required this.multiplier,
    required this.damage,
  });

  final int effectiveAttack;
  final int absorbedAttackPoints;
  final double multiplier;
  final int damage;
}
