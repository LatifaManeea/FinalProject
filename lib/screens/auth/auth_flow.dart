import 'package:flutter/material.dart';

import '../../data/app_repository.dart';
import '../main_shell.dart';
import 'forgot_password_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// Wires Sign In <-> Sign Up <-> Forgot Password together, backed by
/// [appRepository] (a [FakeRepository] for now — the throw shapes it
/// already implements for sign-in/register are exactly what the
/// screens below know how to render as an inline error banner, so
/// swapping in the real Supabase-backed repository later touches
/// nothing here).
class AuthFlow extends StatelessWidget {
  const AuthFlow({super.key});

  void _goToMainShell(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignInScreen(
      onSignIn: (email, password) async {
        await appRepository.signIn(email, password);
        if (context.mounted) _goToMainShell(context);
      },
      onCreateAccount: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignUpScreen(
            onRegister: (name, email, password) async {
              await appRepository.register(email, password, name);
              if (context.mounted) _goToMainShell(context);
            },
            onSignIn: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      onForgotPassword: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForgotPasswordScreen(onSendReset: appRepository.sendPasswordReset),
        ),
      ),
    );
  }
}
