import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import 'vignette_backdrop.dart';

/// Wordmark block shared by every auth screen: the real Marquee Dial
/// mark (`assets/images/app_logo.png`) with its gold glow, "TICKED" in
/// Bebas Neue, and a one-line tagline in the eyebrow style.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 56.0 : 72.0;

    return Column(
      children: [
        SizedBox(
          width: markSize * 1.9,
          height: markSize * 1.9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScreenGlow(size: markSize * 1.9, opacity: 0.3),
              ClipRRect(
                borderRadius: BorderRadius.circular(markSize * 0.26),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: markSize,
                  height: markSize,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        Text('TICKED', style: AppTypography.displayLarge),
        const SizedBox(height: 4),
        Text(
          'NEVER MISS THE FIRST FRAME',
          style: AppTypography.displaySmall.copyWith(color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
