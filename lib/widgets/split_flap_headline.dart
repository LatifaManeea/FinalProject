import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// A headline that flips from [from] to [to] like a departure board.
///
/// Every character is its own little split-flap cell: the top half of the
/// old glyph folds down over the center line, the bottom half of the next
/// glyph folds down to meet it, and it rattles through a couple of random
/// letters on the way. Cells start in a left-to-right, line-by-line ripple,
/// glow [AppColors.gold] while they flip, and settle back to the text color.
///
/// Stateless and driven entirely by [progress] (0 = [from], 1 = [to]) so a
/// Hero flight shuttle can scrub it with the route animation — including
/// backwards on pop.
class SplitFlapHeadline extends StatelessWidget {
  const SplitFlapHeadline({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    required this.style,
  });

  final List<String> from;
  final List<String> to;
  final double progress;
  final TextStyle style;

  /// Intermediate letters shown per flip, before the final one lands.
  static const _rattles = 2;
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Share of the timeline spent staggering starts; the rest is flip time.
  static const _staggerSpan = 0.5;

  @override
  Widget build(BuildContext context) {
    final lineCount = math.max(from.length, to.length);
    final lines = <(String, String)>[];
    for (var l = 0; l < lineCount; l++) {
      final a = l < from.length ? from[l] : '';
      final b = l < to.length ? to[l] : '';
      final width = math.max(a.length, b.length);
      lines.add((a.padRight(width), b.padRight(width)));
    }

    final totalCells = lines.fold<int>(0, (sum, line) => sum + line.$1.length);
    var cellIndex = 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (a, b) in lines)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < a.length; i++)
                _cell(a[i], b[i], cellIndex++, totalCells),
            ],
          ),
      ],
    );
  }

  Widget _cell(String a, String b, int index, int total) {
    final start = total <= 1 ? 0.0 : index / (total - 1) * _staggerSpan;
    final local = ((progress - start) / (1 - _staggerSpan)).clamp(0.0, 1.0);

    final aSize = _glyphSize(a);
    final bSize = _glyphSize(b);
    final width = aSize.width + (bSize.width - aSize.width) * Curves.easeInOut.transform(local);

    // The cell's width eases between the two glyphs; whatever is drawn
    // inside is centered and allowed to spill, so a wide rattle letter in
    // a narrow cell doesn't get pushed to one side.
    Widget sized(Widget child) => SizedBox(
          width: width,
          height: aSize.height,
          child: OverflowBox(minWidth: 0, maxWidth: double.infinity, child: child),
        );

    if (a == b || local == 0 || local == 1) {
      return sized(_Glyph(local < 1 ? a : b, style));
    }

    // old -> random -> random -> new, one flip per step.
    final sequence = [
      a,
      for (var r = 0; r < _rattles; r++) _alphabet[(index * 7 + r * 11 + 3) % _alphabet.length],
      b,
    ];
    final flips = sequence.length - 1;
    final scaled = local * flips;
    final step = math.min(scaled.floor(), flips - 1);
    final flip = scaled - step;

    final glow = math.sin(local * math.pi);
    final color = Color.lerp(style.color, AppColors.gold, glow);

    return sized(
      _FlapCell(
        current: sequence[step],
        next: sequence[step + 1],
        flip: flip,
        style: style.copyWith(color: color),
      ),
    );
  }

  Size _glyphSize(String char) {
    final painter = TextPainter(
      text: TextSpan(text: char, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.char, this.style);

  final String char;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      char,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
    );
  }
}

/// One split-flap cell mid-flip from [current] to [next], [flip] in 0..1.
class _FlapCell extends StatelessWidget {
  const _FlapCell({required this.current, required this.next, required this.flip, required this.style});

  final String current;
  final String next;
  final double flip;
  final TextStyle style;

  Widget _half(String char, {required bool top}) {
    return ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: _Glyph(char, style),
      ),
    );
  }

  Widget _rotated(Widget child, double angle, Alignment hinge) {
    return Transform(
      alignment: hinge,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.004)
        ..rotateX(angle),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstHalf = flip < 0.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top: next glyph waits underneath while the current one folds away.
        Stack(
          children: [
            _half(next, top: true),
            if (firstHalf) _rotated(_half(current, top: true), -flip * math.pi, Alignment.bottomCenter),
          ],
        ),
        // Bottom: current glyph stays until the next one folds down over it.
        Stack(
          children: [
            _half(current, top: false),
            if (!firstHalf) _rotated(_half(next, top: false), (1 - flip) * math.pi, Alignment.topCenter),
          ],
        ),
      ],
    );
  }
}
