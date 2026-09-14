import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import 'split_flap_headline.dart';

/// Cinematic top-of-screen hero for the auth flow: a soft, blurred
/// crop of the real app photo — a vertical beam of gold light, "the
/// lit screen" half of the palette's own tagline, made literal —
/// full-bleed behind an eyebrow line and a bold two-line statement
/// that differs between Sign In and Sign Up.
///
/// This uses `auth_hero_bg.png`, a pre-blurred, edge-trimmed derivative
/// of `app_logo.png` (see `assets/images/`), not the crisp icon file
/// itself — the icon's own rounded-corner card edges showed through as
/// a visible rectangle when used directly as a background, which read
/// as "a photo pasted in" rather than ambient light. Regenerate it by
/// cropping ~16% off each side of `app_logo.png`, upscaling, and
/// applying a heavy Gaussian blur if the source photo ever changes.
///
/// Deliberately separate from [BrandHeader]: that widget is the
/// compact wordmark used on Forgot Password / Check Email, and this
/// one is the bigger, screen-specific moment at the top of the two
/// primary auth screens.
class AuthHero extends StatelessWidget {
  const AuthHero({super.key, required this.headline, this.eyebrow = 'TICKED · EST. 2026', this.height = 340});

  /// One or two short lines, rendered in [AppTypography.displayLarge].
  final List<String> headline;
  final String eyebrow;
  final double height;

  static const heroTag = 'auth-hero';

  @override
  Widget build(BuildContext context) {
    // Same tag on Sign In and Sign Up: when one pushes/pops the other, the
    // photo stays put and only the headline flips, departure-board style.
    return Hero(
      tag: heroTag,
      flightShuttleBuilder: (_, animation, direction, fromContext, toContext) {
        // The hero contexts belong to the Hero widgets, whose parent is
        // the AuthHero on each screen.
        final fromHero = fromContext.findAncestorWidgetOfExactType<AuthHero>()!;
        final toHero = toContext.findAncestorWidgetOfExactType<AuthHero>()!;
        return Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, _) => fromHero._build(
              headline: SplitFlapHeadline(
                from: fromHero.headline,
                to: toHero.headline,
                // The route animation runs 1 -> 0 on pop; flip that so the
                // board always travels from the page we're leaving.
                progress: direction == HeroFlightDirection.push ? animation.value : 1 - animation.value,
                style: AppTypography.displayLarge,
              ),
            ),
          ),
        );
      },
      child: _build(
        headline: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in headline)
              Text(
                line,
                style: AppTypography.displayLarge,
                textAlign: TextAlign.left,
              ),
          ],
        ),
      ),
    );
  }

  Widget _build({required Widget headline}) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/auth_hero_bg.png', fit: BoxFit.cover),
          // Bottom-up vignette so the copy sits on solid dark, not the photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.bg],
                stops: [0.25, 0.92],
              ),
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: AppTypography.overline.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 10),
                headline,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
