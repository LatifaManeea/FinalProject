import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/ticked_text_field.dart';
import '../../widgets/vignette_backdrop.dart';

/// Proposal screen 4 — email reset flow with a confirmation state.
/// [onSendReset] wires to `IntervalRepository.sendPasswordReset`; per
/// the interface it doesn't reveal whether the email exists, so the
/// confirmation state shows regardless of what the backend actually
/// found (never leak account existence through a reset flow).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onSendReset});

  final Future<void> Function(String email) onSendReset;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _emailError;
  String? _formError;
  bool _isLoading = false;
  bool _sent = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    setState(() {
      _formError = null;
      _emailError = email.isEmpty
          ? 'Enter your email'
          : (!_emailPattern.hasMatch(email) ? 'That doesn\'t look like an email' : null);
    });
    if (_emailError != null) return;

    setState(() => _isLoading = true);
    try {
      await widget.onSendReset(email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _formError = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandHeader(compact: true),
                      const SizedBox(height: 28),
                      if (_sent) ..._buildConfirmation() else ..._buildForm(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildForm() {
    return [
      Text('Reset your password', style: AppTypography.displayMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        "We'll send a reset link to your email.",
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
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 28),
      TickedPrimaryButton(label: 'Send reset link', isLoading: _isLoading, onPressed: _submit),
    ];
  }

  List<Widget> _buildConfirmation() {
    return [
      const Icon(Icons.mark_email_read_outlined, color: AppColors.gold, size: 40),
      const SizedBox(height: 18),
      Text('Check your email', style: AppTypography.displayMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'If an account exists for ${_emailController.text.trim()}, a reset link is on its way.',
        style: AppTypography.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      TickedSecondaryButton(label: 'Back to Sign In', onPressed: () => Navigator.of(context).pop()),
    ];
  }
}
