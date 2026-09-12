import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Wires [AppColors] into a [ThemeData] for the handful of Material
/// widgets (inputs, buttons, page transitions) that read their
/// defaults off the ambient theme. Screens still reach for
/// [AppColors]/`AppTypography` directly for anything bespoke, matching
/// the rest of this codebase.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: AppColors.gold,
        onPrimary: AppColors.onGold,
        secondary: AppColors.goldDim,
        onSecondary: AppColors.onGold,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: AppColors.textPrimary,
        outline: AppColors.divider,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textSecondary,
        displayColor: AppColors.textPrimary,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x55EEB154),
        selectionHandleColor: AppColors.gold,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
