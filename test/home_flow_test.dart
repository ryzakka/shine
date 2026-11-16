import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shine/ui/home_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const ShineHomePage(),
    ));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('320px: pertama hanya judul, tombol mulai, dan versi', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, const Size(320, 568));
    expect(find.text('SHINE'), findsOneWidget);
    expect(find.text('MULAI'), findsOneWidget);
    expect(find.text('v1.4.0'), findsOneWidget);
    expect(find.text('LAWAN KOMPUTER'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('MULAI'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('PILIH MODE BERMAIN'), findsOneWidget);
    expect(find.text('MASUK ARENA ONLINE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: menu responsif dengan versi dan opsi main', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, const Size(1280, 800));
    await tester.tap(find.text('MULAI'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('SHINE  •  v1.4.0'), findsOneWidget);
    expect(find.text('LAWAN KOMPUTER'), findsOneWidget);
    expect(find.text('DUA PEMAIN'), findsOneWidget);
    expect(find.text('MASUK ARENA ONLINE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
