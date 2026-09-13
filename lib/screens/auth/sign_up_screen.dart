import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/auth_hero.dart';
import '../../widgets/auth_mode_toggle.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/ticked_text_field.dart';
import '../../widgets/vignette_backdrop.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.onRegister, required this.onSignIn});

  /// Wire this to `IntervalRepository.register(email, password,
  /// displayName)` once the Supabase-backed repository lands. Throw a
  /// message-carrying exception to populate the error banner (e.g. "an
  /// account with that email already exists").
  final Future<void> Function(String displayName, String email, String password) onRegister;

  final VoidCallback onSignIn;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _isLoading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    setState(() {
      _nameError = name.isEmpty ? 'Tell us what to call you' : null;
      _emailError = email.isEmpty
          ? 'Enter your email'
          : (!_emailPattern.hasMatch(email) ? 'That doesn\'t look like an email' : null);
      _passwordError = password.isEmpty
          ? 'Choose a password'
          : (password.length < 8 ? 'At least 8 characters' : null);
      _confirmError = confirm != password ? 'Passwords don\'t match' : null;
    });

    return _nameError == null && _emailError == null && _passwordError == null && _confirmError == null;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.onRegister(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );
    } catch (e) {
      setState(() => _formError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('Exception: ')) return raw.split('Exception: ').last;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHero(headline: ['JOIN THE', 'SHOW.']),
                const SizedBox(height: 28),
                AuthModeToggle(
                  isSignIn: false,
                  onSignInTap: _isLoading ? null : widget.onSignIn,
                  onSignUpTap: null,
                ),
                const SizedBox(height: 24),
                Text(
                  'Create an account to start tracking true start times.',
                  style: AppTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                AuthErrorBanner(message: _formError),
                TickedTextField(
                  label: 'Display name',
                  controller: _nameController,
                  hintText: 'What should we call you?',
                  errorText: _nameError,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 20),
                TickedTextField(
                  label: 'Email',
                  controller: _emailController,
                  hintText: 'you@example.com',
                  errorText: _emailError,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 20),
                TickedTextField(
                  label: 'Password',
                  controller: _passwordController,
                  hintText: '••••••••',
                  errorText: _passwordError,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text('At least 8 characters', style: AppTypography.bodySmall),
                ),
                TickedTextField(
                  label: 'Confirm password',
                  controller: _confirmController,
                  hintText: '••••••••',
                  errorText: _confirmError,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 28),
                TickedPrimaryButton(
                  label: 'Create Account',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR', style: AppTypography.overline),
                    ),
                    const Expanded(child: Divider(color: AppColors.divider)),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TickedSecondaryButton(
                        label: 'Apple',
                        icon: Icons.apple,
                        onPressed: _isLoading ? null : () {},
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TickedSecondaryButton(
                        label: 'Google',
                        onPressed: _isLoading ? null : () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'By continuing you agree to the Terms and Privacy Policy.',
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