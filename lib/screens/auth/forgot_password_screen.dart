import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_back_button.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/auth_hero.dart';
import '../../widgets/code_input.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/ticked_text_field.dart';
import '../../widgets/vignette_backdrop.dart';

/// Proposal screen 4, as a two-step code flow: enter your email, then the
/// one-time code Supabase emails you.
///
/// [onSendReset] sends (or resends) the code. It never reveals whether
/// the email has an account — the code step shows regardless (never leak
/// account existence through a reset flow).
///
/// [onVerifyCode] checks the code and takes it from there (AuthFlow opens
/// Set New Password). Throw a message-carrying exception on a bad code to
/// show it in the banner.
///
/// Same layout as Sign In / Sign Up — the photo hero with a two-line
/// headline over the form — with a back button floating on the photo.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onSendReset, required this.onVerifyCode});

  final Future<void> Function(String email) onSendReset;
  final Future<void> Function(String email, String code) onVerifyCode;

  /// Must match Authentication → Providers → Email → "Email OTP Length"
  /// in the Supabase dashboard.
  static const codeLength = 6;

  /// Supabase allows one email per address per minute by default.
  static const resendCooldown = Duration(seconds: 60);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  String? _emailError;
  String? _formError;
  bool _isLoading = false;
  bool _codeSent = false;
  int _shakeCount = 0;

  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String get _email => _emailController.text.trim();

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = ForgotPasswordScreen.resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _formError = null;
      _emailError = _email.isEmpty
          ? 'Enter your email'
          : (!_emailPattern.hasMatch(_email) ? 'That doesn\'t look like an email' : null);
    });
    if (_emailError != null) return;

    setState(() => _isLoading = true);
    try {
      await widget.onSendReset(_email);
      if (!mounted) return;
      _codeController.clear();
      setState(() => _codeSent = true);
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _formError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_isLoading) return;
    setState(() {
      _formError = null;
      _isLoading = true;
    });
    try {
      await widget.onVerifyCode(_email, code);
    } catch (e) {
      if (!mounted) return;
      _codeController.clear();
      // Re-enable in the same rebuild as the shake, so the input can take
      // focus back for the next attempt.
      setState(() {
        _isLoading = false;
        _formError = _messageFor(e);
        _shakeCount++;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeEmail() {
    _cooldownTimer?.cancel();
    _codeController.clear();
    setState(() {
      _codeSent = false;
      _formError = null;
      _cooldownLeft = 0;
    });
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('Exception: ')) return raw.split('Exception: ').last;
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: Stack(
          children: [
            Column(
              children: [
                // Not part of the Sign In <-> Sign Up flight; this screen
                // just shares the look.
                HeroMode(
                  enabled: false,
                  child: AuthHero(
                    headline: _codeSent ? const ['ENTER THE', 'CODE.'] : const ['FORGOT YOUR', 'PASSWORD?'],
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 28),
                          if (_codeSent) ..._buildCodeStep() else ..._buildEmailStep(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AuthBackButton(
              onPressed: _isLoading ? null : (_codeSent ? _changeEmail : () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEmailStep() {
    return [
      Text(
        "Enter the email on your account and we'll send you a "
        '${ForgotPasswordScreen.codeLength}-digit code to reset your password.',
        style: AppTypography.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 26),
      AuthErrorBanner(message: _formError),
      TickedTextField(
        label: 'Email',
        controller: _emailController,
        hintText: 'you@example.com',
        errorText: _emailError,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _sendCode(),
      ),
      const SizedBox(height: 28),
      TickedPrimaryButton(label: 'Send code', isLoading: _isLoading, onPressed: _sendCode),
      const SizedBox(height: 18),
      _textLink(
        'Remembered it? Sign in',
        onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
      ),
    ];
  }

  List<Widget> _buildCodeStep() {
    return [
      Text.rich(
        TextSpan(
          text: 'We sent a ${ForgotPasswordScreen.codeLength}-digit code to\n',
          children: [
            TextSpan(text: _email, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
        style: AppTypography.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 26),
      AuthErrorBanner(message: _formError),
      CodeInput(
        controller: _codeController,
        length: ForgotPasswordScreen.codeLength,
        enabled: !_isLoading,
        hasError: _formError != null && _codeController.text.isEmpty,
        shakeCount: _shakeCount,
        onCompleted: _verify,
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 24,
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                )
              : Text(
                  "Can't find it? Check your spam folder.",
                  style: AppTypography.bodySmall,
                ),
        ),
      ),
      const SizedBox(height: 18),
      _textLink(
        _cooldownLeft > 0 ? 'Resend code in ${_cooldownLeft}s' : 'Resend code',
        onPressed: _isLoading || _cooldownLeft > 0 ? null : _sendCode,
      ),
      _textLink('Wrong email?', onPressed: _isLoading ? null : _changeEmail, color: AppColors.textSecondary),
    ];
  }

  Widget _textLink(String label, {required VoidCallback? onPressed, Color color = AppColors.gold}) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: AppTypography.label.copyWith(color: onPressed == null ? AppColors.textDisabled : color),
        ),
      ),
    );
  }
}
