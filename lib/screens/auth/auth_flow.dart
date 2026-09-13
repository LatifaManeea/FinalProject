import 'package:flutter/material.dart';

import '../../services/database.dart';
import '../main_shell.dart';
import 'forgot_password_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// Wires Sign In <-> Sign Up <-> Forgot Password
/// together, backed by the real [Database].
///
/// The screens below are unchanged and know nothing about Supabase:
/// they take callbacks, and render whatever exception those throw as an
/// inline banner. [Database.readableAuthError] is what makes that work
/// — it turns Supabase's `AuthException(message: ..., statusCode: ...)`
/// into the plain sentences these screens expect.
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
    final database = Database();

    return SignInScreen(
      onSignIn: (email, password) async {
        await database.signIn(email, password);
        if (context.mounted) _goToMainShell(context);
      },
      onCreateAccount: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (signUpContext) => SignUpScreen(
            onRegister: (name, email, password) async {
              // Confirmation is off, so signing up returns a live
              // session — straight into the app, same as signing in.
              await database.signUp(email, password, name);
              if (signUpContext.mounted) _goToMainShell(signUpContext);
            },
            onSignIn: () => Navigator.of(signUpContext).pop(),
          ),
        ),
      ),
      onForgotPassword: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForgotPasswordScreen(onSendReset: database.sendPasswordReset),
        ),
      ),
    );
  }
}
