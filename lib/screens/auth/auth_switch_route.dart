import 'package:flutter/material.dart';

/// Route used to switch between Sign In and Sign Up.
///
/// It deliberately does almost nothing itself — just a quick crossfade of
/// the (identical) backdrops. The real show happens in the pieces that
/// span both screens:
///
/// * [AuthHero] and [AuthModeToggle] are Heroes, so the photo holds still,
///   the headline flips like a departure board, and the gold pill glides.
/// * [AuthFormEntrance] slides each screen's form out toward its own side
///   of the toggle and the other one in from its side.
class AuthSwitchRoute<T> extends PageRouteBuilder<T> {
  AuthSwitchRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 900),
          reverseTransitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.35, curve: Curves.easeOut)),
            child: child,
          ),
        );
}

/// Wraps an auth screen's form so it slides and fades with the route.
///
/// [side] is where this screen's segment sits on the toggle: -1 for
/// Sign In (left), 1 for Sign Up (right). A form leaves toward its own
/// side and arrives from it, so the motion always follows the gold pill.
class AuthFormEntrance extends StatelessWidget {
  const AuthFormEntrance({super.key, required this.side, required this.child});

  final double side;
  final Widget child;

  static const _travel = 56.0;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return child;

    // This screen arriving (animation 0 -> 1) and something covering it
    // (secondaryAnimation 0 -> 1). Both run in reverse on pop.
    final arriving = CurvedAnimation(
      parent: route.animation ?? kAlwaysCompleteAnimation,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );
    final leaving = CurvedAnimation(
      parent: route.secondaryAnimation ?? kAlwaysDismissedAnimation,
      curve: const Interval(0, 0.35, curve: Curves.easeInCubic),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([arriving, leaving]),
      builder: (context, child) {
        final dx = side * ((1 - arriving.value) + leaving.value) * _travel;
        final opacity = (arriving.value * (1 - leaving.value)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: child,
    );
  }
}
