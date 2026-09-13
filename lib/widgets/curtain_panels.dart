import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Two velvet house-curtain panels that slide open (`openness: 1`) or
/// closed (`openness: 0`) across whatever they're layered on top of.
/// Shared between [SplashScreen]'s own open-then-close and
/// [CurtainPageRoute], which opens a fresh pair over the screen the
/// splash hands off to, so the two feel like one continuous curtain
/// rather than two separate effects.
///
/// Returns the two panels as [Positioned] widgets — they must be added
/// directly as `Stack` children (last, so they sit on top of whatever
/// they're covering), not wrapped in another widget first.
List<Widget> curtainPanels(
  BuildContext context, {
  required double openness,
  double sheen = 0.5,
}) {
  final screenWidth = MediaQuery.of(context).size.width;
  // Wider than half the screen, so the two panels overlap at rest
  // (fully closed) with margin to spare, and each has to travel its
  // own width to clear the opening entirely — the same distance a
  // real house curtain covers.
  final panelWidth = screenWidth * 0.62;
  final travel = panelWidth * openness;

  Widget panel(bool isLeft) {
    return Positioned(
      key: ValueKey('curtain-${isLeft ? 'left' : 'right'}'),
      top: 0,
      bottom: 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      width: panelWidth,
      child: Transform.translate(
        offset: Offset(isLeft ? -travel : travel, 0),
        child: CustomPaint(
          painter: _CurtainPainter(isLeft: isLeft, sheen: sheen),
        ),
      ),
    );
  }

  return [panel(true), panel(false)];
}

/// Paints one velvet curtain panel: repeating fabric folds, a lit inner
/// edge nearest the gap, a thin gold trim, and a dark hem at the floor.
class _CurtainPainter extends CustomPainter {
  _CurtainPainter({required this.isLeft, required this.sheen});

  final bool isLeft;
  final double sheen;

  static final Color _velvetLo = Color.lerp(AppColors.velvet, Colors.black, 0.4)!;
  static final Color _velvetHi = Color.lerp(AppColors.velvet, AppColors.gold, 0.10)!;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Fabric: a repeating vertical band standing in for pleats/folds
    // running the height of the curtain.
    const foldWidth = 46.0;
    final foldShader = LinearGradient(
      colors: [_velvetLo, AppColors.velvet, _velvetHi, AppColors.velvet, _velvetLo],
      stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
      tileMode: TileMode.repeated,
    ).createShader(Rect.fromLTWH(0, 0, foldWidth, size.height));
    canvas.drawRect(rect, Paint()..shader = foldShader);

    // Inner-edge shadow, so the fold nearest the gap reads as receding
    // into shadow rather than sitting flat.
    final innerX = isLeft ? size.width : 0.0;
    const shadowSpan = 90.0;
    final shadowRect = Rect.fromLTWH(isLeft ? size.width - shadowSpan : 0, 0, shadowSpan, size.height);
    final shadowShader = LinearGradient(
      begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0)],
    ).createShader(shadowRect);
    canvas.drawRect(shadowRect, Paint()..shader = shadowShader);

    // A warm sheen catching the folds nearest the light, breathing
    // with [sheen].
    const sheenSpan = 160.0;
    final sheenRect = Rect.fromLTWH(isLeft ? size.width - sheenSpan : 0, 0, sheenSpan, size.height);
    final sheenShader = LinearGradient(
      begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
      end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      colors: [AppColors.goldDim.withOpacity(0.22 * sheen), Colors.transparent],
    ).createShader(sheenRect);
    canvas.drawRect(sheenRect, Paint()..shader = sheenShader);

    // Thin gold trim right at the inner edge.
    final trimPaint = Paint()
      ..color = AppColors.gold.withOpacity((0.30 + 0.5 * sheen).clamp(0.0, 1.0))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(innerX, 0), Offset(innerX, size.height), trimPaint);

    // Hem shadow pooling at the floor.
    final hemHeight = size.height * 0.18;
    final hemRect = Rect.fromLTWH(0, size.height - hemHeight, size.width, hemHeight);
    final hemShader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Colors.black.withOpacity(0.55), Colors.transparent],
    ).createShader(hemRect);
    canvas.drawRect(hemRect, Paint()..shader = hemShader);
  }

  @override
  bool shouldRepaint(covariant _CurtainPainter oldDelegate) =>
      oldDelegate.sheen != sheen || oldDelegate.isLeft != isLeft;
}
