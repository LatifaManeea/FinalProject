import 'package:flutter/material.dart';

/// Interval's colour system — warm cinema direction.
///
/// One accent. A dark room. A lit screen.
///
/// The palette was authored in OKLCH and converted to sRGB; the source
/// value is kept in the comment beside each colour so a shade can be
/// re-derived rather than nudged by eye. Every hue sits between 25 and 80
/// degrees, which is what keeps the greys warm instead of blue.
///
/// The rule that matters: [gold] appears in roughly three places per screen —
/// the number that matters, the one button to press, a thin highlight border.
/// Everywhere else is [bg], [surface] and [textPrimary] doing the work. That is
/// what keeps the app feeling like a theater and not a dashboard.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surfaces — the dark room
  // ---------------------------------------------------------------------------

  /// oklch(11% .012 50) — the app background. The darkest thing on screen.
  static const Color bg = Color(0xFF070402);

  /// oklch(17% .016 50) — cards, sheets, the Schedule Card itself.
  static const Color surface = Color(0xFF150D09);

  /// oklch(22% .018 50) — raised surfaces, input fields, the film span of the
  /// timeline. One step up from [surface], never two.
  static const Color surface2 = Color(0xFF221813);

  /// oklch(28% .016 50) — hairline dividers and unfilled track backgrounds.
  static const Color divider = Color(0xFF302722);

  /// oklch(25% .075 25) — atmosphere only, never UI.
  ///
  /// Deep cinema-curtain red. Use it for a full-bleed gradient wash behind the
  /// Splash or the recap card. Never as a surface a control sits on, never as
  /// text, never as a border — it does not meet contrast against anything and
  /// it is not meant to.
  static const Color velvet = Color(0xFF3E0F0E);

  // ---------------------------------------------------------------------------
  // Accent — the lit screen
  // ---------------------------------------------------------------------------

  /// oklch(80% .13 75) — the one accent. 10.76:1 on [bg].
  ///
  /// The true start time, the running timer, the primary button, the ad block
  /// on the timeline. If a screen has a fourth gold element, one of them is
  /// wrong.
  static const Color gold = Color(0xFFEEB154);

  /// oklch(72% .125 73) — [gold] while a control is held down.
  static const Color goldPressed = Color(0xFFD49740);

  /// oklch(62% .10 70) — borders, dimmed gold, the safe-break spans. 5.53:1 on
  /// [bg], so it is still legible as text where a caption needs warmth.
  static const Color goldDim = Color(0xFFAD7B3D);

  /// oklch(18% .02 60) — foreground on top of a [gold] fill. 9.05:1 on [gold].
  ///
  /// Never use [bg] here: pure-dark on gold reads as a hole punched in the
  /// button rather than as a label.
  static const Color onGold = Color(0xFF211A12);

  // ---------------------------------------------------------------------------
  // Text — warm off-white, three weights of emphasis
  // ---------------------------------------------------------------------------

  /// oklch(95% .012 80) — warm off-white. Headlines and body. 17.70:1 on [bg].
  static const Color textPrimary = Color(0xFFF3EEE6);

  /// oklch(80% .012 70) — secondary copy, labels. 10.98:1 on [bg].
  static const Color textSecondary = Color(0xFFC3BDB6);

  /// oklch(65% .012 60) — captions, timestamps, the "9:17" on a ticket stub.
  /// 6.33:1 on [bg] — passes AA, and is the dimmest text the system allows.
  static const Color textTertiary = Color(0xFF958E88);

  /// Text on a surface that is disabled. Decorative only — never the sole
  /// carrier of meaning, because it does not meet contrast.
  static const Color textDisabled = Color(0xFF6B645E);

  // ---------------------------------------------------------------------------
  // Timeline segments
  // ---------------------------------------------------------------------------
  //
  // The segmented timeline (F4) draws four spans: ad block, film, safe breaks
  // and credits. They separate by *value*, not by hue — introducing a second
  // accent colour here is what would turn the screen into a dashboard. The ad
  // block is gold because it is the thing the project measured and the thing
  // the demo points at.

  /// The advertising block — the measured span, drawn in the accent.
  static const Color timelineAds = gold;

  /// The film itself — the long, quiet span.
  static const Color timelineFilm = surface2;

  /// A safe break — dimmed gold against the film.
  static const Color timelineBreak = goldDim;

  /// Closing credits. Omitted entirely when `films.credits_start_min` is null,
  /// so this colour is allowed to be nearly invisible.
  static const Color timelineCredits = divider;

  /// The playhead marking the current minute during a live session.
  static const Color timelinePlayhead = textPrimary;

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// oklch(63% .17 27) — validation failures, wrong credentials, network
  /// errors. 5.40:1 on [bg]. Warm enough to belong to this palette; distinct
  /// enough from [gold] that the two never read as the same signal.
  static const Color error = Color(0xFFDD574E);

  /// A tinted background for an inline error row.
  static const Color errorSurface = Color(0xFF2A100E);

  /// Skeleton and shimmer base while breaks are being generated.
  static const Color skeleton = Color(0xFF1B120D);
}
