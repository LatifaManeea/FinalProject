import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Cinematic top-of-screen hero for the auth flow: a vertical beam of
/// gold light — "the lit screen" half of the palette's own tagline,
/// made literal — behind an eyebrow line and a bold two-line
/// statement that differs between Sign In and Sign Up.
///
/// Deliberately separate from [BrandHeader]: that widget is the
/// compact wordmark used on Forgot Password / Check Email, and this
/// one is the bigger, screen-specific moment at the top of the two
/// primary auth screens.
class AuthHero extends StatelessWidget {
  const AuthHero({super.key, required this.headline, this.eyebrow = 'TICKED · EST. 2026'});

  /// One or two short lines, rendered in [AppTypography.displayLarge].
  final List<String> headline;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const _LightBeam(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow,
                  style: AppTypography.overline.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 10),
                for (final line in headline)
                  Text(
                    line,
                    style: AppTypography.displayLarge,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The thin vertical column of gold light behind the headline.
class _LightBeam extends StatelessWidget {
  const _LightBeam();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 3,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.gold.withOpacity(0),
              AppColors.gold,
              AppColors.gold.withOpacity(0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withOpacity(0.55), blurRadius: 28, spreadRadius: 8),
          ],
        ),
      ),
    );
  }
}