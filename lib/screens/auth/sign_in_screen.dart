import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/ticked_text_field.dart';
import '../../widgets/vignette_backdrop.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onForgotPassword,
  });

  /// Wire this to `IntervalRepository.signIn(email, password)` once the
  /// Supabase-backed repository lands. Throw a message-carrying
  /// exception (or let a network exception surface) to populate the
  /// error banner — the two states the proposal calls out are wrong
  /// credentials and network failure, and both just flow through here.
  final Future<void> Function(String email, String password) onSignIn;

  final VoidCallback onCreateAccount;
  final VoidCallback onForgotPassword;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _isLoading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _emailError = email.isEmpty
          ? 'Enter your email'
          : (!_emailPattern.hasMatch(email) ? 'That doesn\'t look like an email' : null);
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });

    return _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.onSignIn(_emailController.text.trim(), _passwordController.text);
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
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const BrandHeader(),
                const SizedBox(height: 40),
                AuthErrorBanner(message: _formError),
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
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton(
                      onPressed: _isLoading ? null : widget.onForgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot password?',
                        style: AppTypography.label.copyWith(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                TickedPrimaryButton(
                  label: 'Sign In',
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
                TickedSecondaryButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple,
                  onPressed: _isLoading ? null : () {},
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New here? ', style: AppTypography.bodyMedium),
                    GestureDetector(
                      onTap: _isLoading ? null : widget.onCreateAccount,
                      child: Text(
                        'Create an account',
                        style: AppTypography.label.copyWith(color: AppColors.gold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
