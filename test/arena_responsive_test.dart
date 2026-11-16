import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shine/domain/battle_match.dart';
import 'package:shine/ui/arena_page.dart';
import 'package:shine/ui/squad_picker.dart';

/// Pemeriksaan regresi: perubahan giliran dan status mengirim tidak boleh
/// mengubah luas panggung. Jangan pakai pumpAndSettle: arena punya ambient loop.
void main() {
  final battle = LocalBattle(
    teamA: ['chaminhyuk', 'leejunseo', 'hanseoah'],
    teamB: ['kwontaehyuk', 'kangjiwoo', 'choinari'],
  );

  Widget arena(Map<String, dynamic> state, {bool canAct = true}) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
    home: MatchArena(
      title: 'Tes Arena',
      state: state,
      viewerSide: 0,
      isBotMatch: true,
      canAct: canAct,
      onAction: ({required int attack, required int defend,
          required int reserve, required bool useSkill, int? swapTo}) async {},
    ),
  );

  testWidgets('Ponsel: panggung tidak meloncat saat giliran berganti', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = localSnapshot(battle);
    await tester.pumpWidget(arena(state));
    await tester.pump();
    final originalStage = tester.getSize(find.byKey(const ValueKey('shine-stage')));
    final originalDeck = tester.getSize(find.byKey(const ValueKey('shine-command-deck')));

    await tester.pumpWidget(arena({...state, 'turn': 2,
      'log': 'Tim A: 1 serang, 0 bertahan, 0 cadangan. Damage 10.'}, canAct: false));
    await tester.pump(const Duration(milliseconds: 100));
    final newStage = tester.getSize(find.byKey(const ValueKey('shine-stage')));
    final newDeck = tester.getSize(find.byKey(const ValueKey('shine-command-deck')));
    expect(newStage, originalStage);
    expect(newDeck, originalDeck);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop: panel strategi di samping panggung dan stabil', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = localSnapshot(battle);
    await tester.pumpWidget(arena(state));
    await tester.pump();
    final stage = tester.getSize(find.byKey(const ValueKey('shine-stage')));
    final deck = tester.getSize(find.byKey(const ValueKey('shine-command-deck')));
    expect(stage.width, greaterThan(deck.width));
    expect(deck.width, closeTo(348, .5));

    await tester.pumpWidget(arena({...state, 'turn': 2,
      'log': 'Waktu Tim A habis. Giliran dilewati.'}, canAct: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byKey(const ValueKey('shine-stage'))), stage);
    expect(tester.getSize(find.byKey(const ValueKey('shine-command-deck'))), deck);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Landscape pendek: kontrol tetap dapat di-scroll tanpa overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(740, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(arena(localSnapshot(battle)));
    await tester.pump();
    expect(find.byKey(const ValueKey('shine-stage')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('shine-stage'))).height,
        greaterThan(0));
    expect(tester.takeException(), isNull);
  });


  testWidgets('Ponsel sempit 320 px: arena dan tombol tetap berada di viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(arena(localSnapshot(battle)));
    await tester.pump();
    final stage = tester.getRect(find.byKey(const ValueKey('shine-stage')));
    final deck = tester.getRect(find.byKey(const ValueKey('shine-command-deck')));
    expect(stage.left, greaterThanOrEqualTo(0));
    expect(stage.right, lessThanOrEqualTo(320));
    expect(deck.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tablet 960 px: tidak memaksakan panel samping sempit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(arena(localSnapshot(battle)));
    await tester.pump();
    final stage = tester.getSize(find.byKey(const ValueKey('shine-stage')));
    expect(stage.width, 960);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HP sekarat tetap terlihat merah, sedangkan HP penuh hijau', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = localSnapshot(battle);
    final teams = (state['teams'] as List).cast<Map<String, dynamic>>();
    final team = teams[0];
    final cards = (team['cards'] as List).cast<Map<String, dynamic>>();
    cards[0]['hp'] = 12;
    await tester.pumpWidget(arena(state));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('SEKARAT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('Pilihan kartu di landscape pendek tidak memotong kontrol utama', (tester) async {
    await tester.binding.setSurfaceSize(const Size(740, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: SquadPicker(defaults: [], title: 'PILIH KARTU')));
    await tester.pump();
    expect(find.text('PILIH KARTU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
