import 'dart:math';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../services/database.dart';
import '../widgets/curtain_panels.dart';
import '../widgets/curtain_route.dart';
import '../widgets/vignette_backdrop.dart';
import 'auth/auth_flow.dart';
import 'main_shell.dart';

/// The first thing anyone sees: two searchlights swing in and settle on
/// velvet house curtains, which part to reveal the brand the way a
/// premiere puts a name in lights. It holds so there's time to actually
/// read it, then the curtains sweep shut again — and open right back up
/// on whichever screen comes next (see [CurtainPageRoute]), so the
/// whole thing reads as one continuous motion rather than a splash
/// effect bolted onto an unrelated page change. While it plays,
/// [Database.getCurrentUser] checks whether Supabase still has a
/// persisted session: signed-in goes straight to [MainShell], everyone
/// else lands on [AuthFlow].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // The reveal itself: curtains swinging open, spotlights finding the
  // name, the wordmark and tagline settling in.
  static const _entranceDuration = Duration(milliseconds: 3800);
  // How long it sits fully revealed, read-able, before closing again.
  static const _holdDuration = Duration(milliseconds: 1300);
  // The curtains sweeping shut at the end.
  static const _closeDuration = Duration(milliseconds: 700);

  static const _letters = 'TICKED';

  // Spotlights: fade in, swing back and forth a few times with
  // decaying amplitude until they settle pointing at the wordmark,
  // then fade out once the tagline is on its way in.
  static const _spotlightFadeInStart = 0.05;
  static const _spotlightFadeInEnd = 0.16;
  static const _spotlightSweepStart = 0.08;
  static const _spotlightSweepEnd = 0.50;
  static const _spotlightSettleAngle = 0.62; // radians, tilt from vertical
  static const _spotlightFadeOutStart = 0.58;
  static const _spotlightFadeOutEnd = 0.80;

  late final AnimationController _entrance;
  late final AnimationController _glow;
  late final AnimationController _close;

  late final Animation<double> _partCurve;
  late final Animation<Offset> _wordmarkSlide;
  late final Animation<double> _ruleGrow;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(vsync: this, duration: _entranceDuration)..forward();
    // A slow warm flicker behind the wordmark, like a projector bulb
    // that never fully settles.
    _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    // Plays once, on the way out: the curtains sweeping shut.
    _close = AnimationController(vsync: this, duration: _closeDuration);

    _partCurve = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.06, 0.34, curve: Curves.easeInOutCubic),
    );
    _wordmarkSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.40, 0.62, curve: Curves.easeOutCubic),
    ).drive(Tween(begin: const Offset(0, 0.3), end: Offset.zero));
    _ruleGrow = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.64, 0.84, curve: Curves.easeOutCubic),
    );
    _taglineFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.74, 0.94, curve: Curves.easeOut),
    );

    _route();
  }

  /// Fade-in envelope for letter [i] of six, staggered slightly so the
  /// wordmark seems to catch the light one letter at a time rather than
  /// snapping on all at once.
  double _letterEnvelope(int i) {
    const stagger = 0.035;
    const duration = 0.28;
    final start = 0.40 + i * stagger;
    final t = ((_entrance.value - start) / duration).clamp(0.0, 1.0);
    return Curves.easeOut.transform(t);
  }

  /// How lit the two spotlights are right now: in quickly, out again
  /// once the wordmark has caught the light and the tagline is due.
  double _spotlightIntensity(double t) {
    final fadeIn = ((t - _spotlightFadeInStart) / (_spotlightFadeInEnd - _spotlightFadeInStart))
        .clamp(0.0, 1.0);
    final fadeOut = 1 -
        ((t - _spotlightFadeOutStart) / (_spotlightFadeOutEnd - _spotlightFadeOutStart))
            .clamp(0.0, 1.0);
    return (fadeIn * fadeOut).clamp(0.0, 1.0);
  }

  /// The spotlights' angle from vertical: a few decaying swings before
  /// settling on [_spotlightSettleAngle], the way two searchlights hunt
  /// for a name before locking onto it.
  double _spotlightAngle(double t) {
    final sweepT =
        ((t - _spotlightSweepStart) / (_spotlightSweepEnd - _spotlightSweepStart)).clamp(0.0, 1.0);
    final amplitude = (1 - Curves.easeIn.transform(sweepT)) * 0.5;
    final oscillation = sin(sweepT * pi * 3.4);
    return _spotlightSettleAngle + amplitude * oscillation;
  }

  Future<void> _route() async {
    final stopwatch = Stopwatch()..start();
    final user = await Database().getCurrentUser();

    // Let the reveal play out in full on the fast path, so the splash
    // reads as a moment rather than a flicker.
    final remaining = _entranceDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;
    // Give it a moment to actually be read before it closes again.
    await Future.delayed(_holdDuration);

    if (!mounted) return;
    // Sweep the curtains shut before cutting away — the close every
    // reel ends on, not just a fade.
    await _close.forward();
    if (!mounted) return;

    // The next screen arrives already covered by closed curtains and
    // opens them itself (see CurtainPageRoute), so this close and that
    // open read as one continuous motion.
    Navigator.of(context).pushReplacement(
      CurtainPageRoute(child: user != null ? const MainShell() : const AuthFlow()),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _glow.dispose();
    _close.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _glow, _close]),
        builder: (context, _) {
          final t = _entrance.value;
          // 0 = fully closed, 1 = fully open. The entrance opens them;
          // _close (0 -> 1 on exit) sweeps them shut again on top of
          // wherever the entrance left off.
          final openness = (_partCurve.value * (1 - _close.value)).clamp(0.0, 1.0);
          final contentEnvelope = 1 - _close.value;
          final sheen = (0.4 + 0.35 * sin(_glow.value * pi)) * (0.35 + 0.65 * openness);
          final spotlightIntensity = _spotlightIntensity(t) * contentEnvelope;
          final spotlightAngle = _spotlightAngle(t);

          return Stack(
            fit: StackFit.expand,
            children: [
              VignetteBackdrop(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildSpotlights(spotlightIntensity, spotlightAngle),
                    _buildContent(contentEnvelope),
                  ],
                ),
              ),
              // The curtains sit on top of everything else, so they
              // fully mask the stage while closed regardless of how
              // the content's own fade timing lines up.
              ...curtainPanels(context, openness: openness, sheen: sheen),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpotlights(double intensity, double angle) {
    if (intensity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _SpotlightPainter(theta: angle, intensity: intensity),
      ),
    );
  }

  Widget _buildContent(double envelope) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWordmark(envelope),
          const SizedBox(height: 10),
          _buildRule(envelope),
          const SizedBox(height: 14),
          _buildTagline(envelope),
        ],
      ),
    );
  }

  Widget _buildWordmark(double envelope) {
    final style = AppTypography.displayLarge.copyWith(fontSize: 64, letterSpacing: 3);
    return FractionalTranslation(
      translation: _wordmarkSlide.value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _letters.length; i++)
            _buildLetter(i, style, envelope),
        ],
      ),
    );
  }

  Widget _buildLetter(int i, TextStyle style, double envelope) {
    final a = (_letterEnvelope(i) * envelope).clamp(0.0, 1.0);
    return Opacity(
      opacity: a,
      child: Transform.translate(
        offset: Offset(0, (1 - a) * 14),
        child: Text(_letters[i], style: style),
      ),
    );
  }

  Widget _buildRule(double envelope) {
    final grow = (_ruleGrow.value * envelope).clamp(0.0, 1.0);
    return Opacity(
      opacity: grow,
      child: Container(height: 2, width: 46 * grow, color: AppColors.goldDim),
    );
  }

  Widget _buildTagline(double envelope) {
    final a = (_taglineFade.value * envelope).clamp(0.0, 1.0);
    return Opacity(
      opacity: a,
      child: Text(
        'NEVER MISS THE FIRST FRAME',
        style: AppTypography.displaySmall.copyWith(color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Two searchlight beams swinging in from the top corners and settling
/// on the wordmark — a name getting its own spotlight, the way a movie
/// premiere lights up the star on the marquee.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.theta, required this.intensity});

  /// Angle from straight-down, in radians. The left beam tilts right by
  /// this much; the right beam mirrors it, tilting left.
  final double theta;
  final double intensity;

  static const _halfWidth = 9 * pi / 180;
  static const _coreHalfWidth = 2.6 * pi / 180;
  static final Color _hot = Color.lerp(AppColors.gold, Colors.white, 0.35)!;

  Offset _dir(double angle) => Offset(sin(angle), cos(angle));

  Path _cone(Offset origin, double angle, double halfWidth, double length) {
    final left = origin + _dir(angle - halfWidth) * length;
    final right = origin + _dir(angle + halfWidth) * length;
    return Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
  }

  void _paintBeam(Canvas canvas, Offset origin, double angle, double length) {
    final falloffRect = Rect.fromCircle(center: origin, radius: length);

    final softPath = _cone(origin, angle, _halfWidth, length);
    final softShader = RadialGradient(
      colors: [AppColors.gold.withOpacity(0.20 * intensity), AppColors.gold.withOpacity(0)],
    ).createShader(falloffRect);
    canvas.drawPath(softPath, Paint()..shader = softShader..blendMode = BlendMode.plus);

    final corePath = _cone(origin, angle, _coreHalfWidth, length);
    final coreShader = RadialGradient(
      colors: [_hot.withOpacity(0.55 * intensity), _hot.withOpacity(0)],
    ).createShader(falloffRect);
    canvas.drawPath(corePath, Paint()..shader = coreShader..blendMode = BlendMode.plus);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final length = size.height * 1.3;
    _paintBeam(canvas, Offset.zero, theta, length);
    _paintBeam(canvas, Offset(size.width, 0), -theta, length);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.theta != theta || oldDelegate.intensity != intensity;
}
