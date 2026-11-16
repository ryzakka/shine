import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'online/shine_service.dart';
import 'ui/home_page.dart';

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
    const gold = Color(0xFFEFC483);
    return MaterialApp(
      title: 'Shine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10101B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          surface: const Color(0xFF1E1A2A),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF201D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF10101B)),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          ),
        ),
      ),
      home: const ShineHomePage(),
    );
  }
}
