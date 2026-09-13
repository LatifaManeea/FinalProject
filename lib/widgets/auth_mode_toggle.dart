import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// The Sign In / Sign Up segmented switch shown near the top of both
/// auth screens. Each screen renders itself as the active segment;
/// tapping the *inactive* segment fires the existing [AuthFlow]
/// navigation callback (`onCreateAccount` / `onSignIn`) — this widget
/// holds no navigation logic of its own, it just shows the choice.
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
      child: Row(
        children: [
          Expanded(child: _Segment(label: 'Sign in', active: isSignIn, onTap: onSignInTap)),
          Expanded(child: _Segment(label: 'Sign up', active: !isSignIn, onTap: onSignUpTap)),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: AppTypography.label.copyWith(
            color: active ? AppColors.onGold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}