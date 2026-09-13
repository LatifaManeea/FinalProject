import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  await dotenv.load();

  await Supabase.initialize(
    url: dotenv.get("SUPABASE_URL"),
    publishableKey: dotenv.get("SUPABASE_PUBLISHABLE_KEY"),
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ticked',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}
