import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Round, translucent back button that floats over [AuthHero]'s photo on
/// the secondary auth screens (Forgot Password, Set New Password).
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: AppColors.bg.withValues(alpha: 0.45),
          shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
