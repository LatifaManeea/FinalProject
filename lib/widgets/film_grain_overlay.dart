import 'dart:math';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// The faint sensor-grain / dust texture from the design canvas — a
/// sparse field of static, seeded dots painted at very low opacity, so
/// the dark surfaces never read as flat digital black.
class FilmGrainOverlay extends StatelessWidget {
  const FilmGrainOverlay({super.key, this.opacity = 0.05, this.density = 900});

  final double opacity;
  final int density;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          painter: _GrainPainter(density: density),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.density});

  final int density;
  static final Random _rng = Random(1974);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.textPrimary;
    for (var i = 0; i < density; i++) {
      final dx = _rng.nextDouble() * size.width;
      final dy = _rng.nextDouble() * size.height;
      final r = _rng.nextDouble() * 0.6 + 0.3;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) => false;
}
