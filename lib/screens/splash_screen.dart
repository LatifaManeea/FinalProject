import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../data/app_repository.dart';
import '../widgets/brand_header.dart';
import '../widgets/vignette_backdrop.dart';
import 'auth/auth_flow.dart';
import 'main_shell.dart';

/// Proposal screen 1 — checks the existing auth session and routes
/// accordingly. [TickedRepository.currentUser] is what the real
/// Supabase-backed repository will answer from a persisted session;
/// the fake one just reports whatever `signOut`/`signIn` last left it
/// as, which is enough to exercise both branches today.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final stopwatch = Stopwatch()..start();
    final user = await appRepository.currentUser();

    // Keep the brand mark on screen for at least this long so the
    // splash reads as a moment, not a flicker, on the fast path.
    const minimumDisplay = Duration(milliseconds: 900);
    final remaining = minimumDisplay - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => user != null ? const MainShell() : const AuthFlow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: Center(
          child: BrandHeader(),
        ),
      ),
    );
  }
}
