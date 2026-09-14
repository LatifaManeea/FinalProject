import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_back_button.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/auth_hero.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/ticked_text_field.dart';
import '../../widgets/vignette_backdrop.dart';

/// The last step of a password reset. By the time this shows, the emailed
/// code has already been traded for a (recovery) session, so all that's
/// left is choosing the new password.
///
/// [onSave] should update the password and move on into the app;
/// [onCancel] should drop the recovery session and return to Sign In.
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key, required this.onSave, required this.onCancel});

  final Future<void> Function(String password) onSave;
  final Future<void> Function() onCancel;

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    final password = _passwordController.text;
    setState(() {
      _passwordError = password.isEmpty
          ? 'Choose a password'
          : (password.length < 8 ? 'At least 8 characters' : null);
      _confirmError = _confirmController.text != password ? 'Passwords don\'t match' : null;
    });
    return _passwordError == null && _confirmError == null;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!_validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.onSave(_passwordController.text);
    } catch (e) {
      if (mounted) setState(() => _formError = _messageFor(e));
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
    return PopScope(
      // A system back would leave a half-finished recovery session
      // signed in; route it through cancel instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isLoading) widget.onCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: VignetteBackdrop(
          child: Stack(
            children: [
              Column(
                children: [
                  const HeroMode(
                    enabled: false,
                    child: AuthHero(headline: ['A FRESH', 'START.']),
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
                            Text(
                              'Choose a new password for your account.',
                              style: AppTypography.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 26),
                            AuthErrorBanner(message: _formError),
                            TickedTextField(
                              label: 'New password',
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
                              label: 'Confirm new password',
                              controller: _confirmController,
                              hintText: '••••••••',
                              errorText: _confirmError,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 28),
                            TickedPrimaryButton(
                              label: 'Save password',
                              isLoading: _isLoading,
                              onPressed: _submit,
                            ),
                            const SizedBox(height: 18),
                            Center(
                              child: TextButton(
                                onPressed: _isLoading ? null : widget.onCancel,
                                child: Text(
                                  'Cancel',
                                  style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AuthBackButton(onPressed: _isLoading ? null : widget.onCancel),
            ],
          ),
        ),
      ),
    );
  }
}
