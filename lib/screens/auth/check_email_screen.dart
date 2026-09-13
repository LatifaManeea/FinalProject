import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';

/// Where sign-up lands. Email confirmation is on, so registering does
/// not sign anyone in — Supabase sends a link and there is no session
/// until it is clicked.
///
/// The link opens in a browser rather than the app (no deep linking
/// configured), so this screen's job is to say so plainly and send the
/// user back to sign in once they are done. The resend button matters
/// more than it looks: confirmation mail lands in spam often enough
/// that without it, a user whose email never arrives has no way
/// forward except making a second account.
class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({
    super.key,
    required this.email,
    required this.onResend,
    required this.onBackToSignIn,
  });

  /// The address the link was sent to — shown back so a typo is obvious.
  final String email;

  final Future<void> Function(String email) onResend;
  final VoidCallback onBackToSignIn;

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  /// Supabase rate-limits confirmation mail, so a user who taps twice
  /// gets an error instead of a second email. Better to hold the button
  /// than to explain the failure.
  static const int resendCooldownSeconds = 60;

  String? _formError;
  String? _notice;
  bool _isSending = false;
  int _secondsLeft = 0;
  Timer? _cooldown;

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _secondsLeft = resendCooldownSeconds);

    _cooldown?.cancel();
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();

      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _formError = null;
      _notice = null;
      _isSending = true;
    });

    try {
      await widget.onResend(widget.email);
      if (!mounted) return;
      setState(() => _notice = 'Sent again — it can take a minute to arrive.');
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('Exception: ')) return raw.split('Exception: ').last;
    return raw;
  }

  String get _resendLabel {
    if (_secondsLeft > 0) return 'Resend in ${_secondsLeft}s';
    return 'Resend email';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                const BrandHeader(compact: true),
                Padding(
                  padding: const EdgeInsets.only(top: 34, bottom: 18),
                  child: Icon(Icons.mark_email_unread_outlined, size: 56, color: AppColors.gold),
                ),
                Text(
                  'Check your email',
                  style: AppTypography.displayMedium,
                  textAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(
                    'We sent a confirmation link to',
                    style: AppTypography.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                Text(
                  widget.email,
                  style: AppTypography.label.copyWith(color: AppColors.gold),
                  textAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 26),
                  child: Text(
                    'Open it, confirm your account, then come back here '
                    'and sign in.',
                    style: AppTypography.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                AuthErrorBanner(message: _formError),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      _notice!,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.gold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                TickedPrimaryButton(
                  label: 'Back to Sign In',
                  onPressed: widget.onBackToSignIn,
                ),
                const SizedBox(height: 16),
                TickedSecondaryButton(
                  label: _resendLabel,
                  icon: Icons.refresh,
                  onPressed: (_isSending || _secondsLeft > 0) ? null : _resend,
                ),
                const SizedBox(height: 28),
                Text(
                  'No email? Check your spam folder before resending.',
                  style: AppTypography.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
