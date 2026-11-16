import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'online/shine_service.dart';
import 'ui/home_page.dart';
import 'ui/shine_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: ShineSupabaseConfig.url,
    publishableKey: ShineSupabaseConfig.publishableKey,
  );
  runApp(const ShineApp());
}

class ShineApp extends StatelessWidget {
  const ShineApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: shineInk,
        colorScheme: ColorScheme.fromSeed(
          seedColor: shineGold,
          brightness: Brightness.dark,
          primary: shineGold,
          onPrimary: const Color(0xFF241A08),
          surface: shinePanel,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF201D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: shineGold),
          actionsIconTheme: IconThemeData(color: shineGold),
          titleTextStyle: TextStyle(color: shineGold, fontSize: 15,
              fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1E1A2C),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: shineGold.withValues(alpha: .3))),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1A1727),
          showDragHandle: true,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2438),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white.withValues(alpha: .05),
          selectedColor: shineGold.withValues(alpha: .24),
          side: const BorderSide(color: Colors.white24),
          shape: const StadiumBorder(),
          checkmarkColor: shineGold,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          ),
        ),
      ),
      home: const ShineHomePage(),
    );
  }
}