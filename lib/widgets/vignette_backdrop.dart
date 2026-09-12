import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'film_grain_overlay.dart';

/// Shared "moody theater" backdrop for full-bleed screens: a velvet
/// wash fading into [AppColors.bg], an edge vignette, and grain — the
/// same three layers behind every screen in the design canvas.
///
/// [AppColors.velvet] is documented as atmosphere-only, never UI — this
/// widget is the one place that's true by construction, since nothing
/// interactive ever sits directly on it.
class VignetteBackdrop extends StatelessWidget {
  const VignetteBackdrop({super.key, this.child, this.showVelvet = true});

  final Widget? child;
  final bool showVelvet;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.bg),
        if (showVelvet)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.46],
                colors: [AppColors.velvet, AppColors.bg],
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.1,
              stops: [0.4, 1.0],
              colors: [Colors.transparent, Color(0x8C000000)],
            ),
          ),
        ),
        const FilmGrainOverlay(),
        if (child != null) child!,
      ],
    );
  }
}

/// A soft radial gold glow, dropped behind hero elements (the brand
/// mark, a countdown dial) the way `.screen-glow` worked in the
/// original mockups.
class ScreenGlow extends StatelessWidget {
  const ScreenGlow({super.key, this.size = 420, this.opacity = 0.22});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.gold.withOpacity(opacity),
              AppColors.gold.withOpacity(0),
            ],
            stops: const [0.0, 0.65],
          ),
        ),
      ),
    );
  }
}
