import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// The Sign In / Sign Up segmented switch shown near the top of both
/// auth screens. Each screen renders itself as the active segment;
/// tapping the *inactive* segment fires the existing [AuthFlow]
/// navigation callback (`onCreateAccount` / `onSignIn`) — this widget
/// holds no navigation logic of its own, it just shows the choice.
///
/// It is a [Hero], so while the route between the two screens animates
/// the gold pill glides across instead of jumping — stretching toward
/// its destination and snapping back, a little liquid.
class AuthModeToggle extends StatelessWidget {
  const AuthModeToggle({
    super.key,
    required this.isSignIn,
    required this.onSignInTap,
    required this.onSignUpTap,
  });

  final bool isSignIn;

  /// Pass `null` for the segment that is already active (e.g. Sign In
  /// screen passes `null` here) — the other segment gets the real
  /// navigation callback.
  final VoidCallback? onSignInTap;
  final VoidCallback? onSignUpTap;

  static const heroTag = 'auth-mode-toggle';

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      flightShuttleBuilder: (_, animation, direction, fromContext, toContext) {
        // The hero contexts belong to the Hero widgets, whose parent is
        // the AuthModeToggle on each screen.
        final from = fromContext.findAncestorWidgetOfExactType<AuthModeToggle>()!;
        final to = toContext.findAncestorWidgetOfExactType<AuthModeToggle>()!;
        final begin = from.isSignIn ? 0.0 : 1.0;
        final end = to.isSignIn ? 0.0 : 1.0;
        return Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, _) {
              // Route animation runs 1 -> 0 on pop; normalize to 0 -> 1.
              final t = direction == HeroFlightDirection.push ? animation.value : 1 - animation.value;
              return _ToggleTrack(position: begin + (end - begin) * t);
            },
          ),
        );
      },
      child: _ToggleTrack(
        position: isSignIn ? 0 : 1,
        onSignInTap: onSignInTap,
        onSignUpTap: onSignUpTap,
      ),
    );
  }
}

/// [position] 0 = pill under "Sign in", 1 = pill under "Sign up".
class _ToggleTrack extends StatelessWidget {
  const _ToggleTrack({required this.position, this.onSignInTap, this.onSignUpTap});

  final double position;
  final VoidCallback? onSignInTap;
  final VoidCallback? onSignUpTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = constraints.maxWidth / 2;
          // The two edges ride different curves: whichever edge faces the
          // destination leads, the other trails, so the pill stretches
          // mid-travel and settles back to one segment wide.
          final left = segment * Curves.easeInCubic.transform(position);
          final right = segment + segment * Curves.easeOutCubic.transform(position);

          return Stack(
            children: [
              Positioned(
                left: left,
                width: right - left,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.28),
                        blurRadius: 14,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _Segment(label: 'Sign in', activeness: 1 - position, onTap: onSignInTap)),
                  Expanded(child: _Segment(label: 'Sign up', activeness: position, onTap: onSignUpTap)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.activeness, required this.onTap});

  final String label;
  final double activeness;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(
          label,
          style: AppTypography.label.copyWith(
            color: Color.lerp(AppColors.textSecondary, AppColors.onGold, activeness),
          ),
        ),
      ),
    );
  }
}
