import 'package:flutter/material.dart';

import 'curtain_panels.dart';

/// A page route that arrives already covered by closed curtains and
/// opens them as it enters. [SplashScreen] hands off to a screen
/// pushed with this route right after its own curtains finish
/// closing, so the cut lands on two matching closed-curtain frames and
/// the whole thing reads as one continuous open → close → open motion
/// instead of a splash effect and a separate, unrelated page change.
class CurtainPageRoute<T> extends PageRouteBuilder<T> {
  CurtainPageRoute({required this.child})
      : super(
          transitionDuration: const Duration(milliseconds: 950),
          reverseTransitionDuration: const Duration(milliseconds: 950),
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
            final openness = Curves.easeInOutCubic.transform(animation.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                pageChild,
                ...curtainPanels(context, openness: openness, sheen: 0.55),
              ],
            );
          },
        );

  final Widget child;
}
