import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../auth/presentation/auth_controller.dart';

/// The Apple / Google provider calls, lifted verbatim from the existing
/// welcome screen so the onboarding sheet makes exactly the same requests.
/// Overridable ([obSocialSignInProvider]) so widget tests never touch the
/// platform plugins.
class ObSocialSignIn {
  const ObSocialSignIn();

  /// Runs the Apple flow and signs in. Throws on cancel/failure.
  Future<void> apple(AuthController auth) async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Apple did not return an identity token');
    }
    // Exchanged server-side for a refresh token so account deletion can
    // revoke the grant; may be absent on some re-auth paths.
    final authorizationCode = credential.authorizationCode;
    final parts = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    await auth.signInWithApple(
      idToken,
      fullName: parts.isEmpty ? null : parts.join(' '),
      authorizationCode: authorizationCode,
    );
  }

  /// Runs the Google flow and signs in. Returns false when the user backed
  /// out; throws on failure.
  Future<bool> google(AuthController auth) async {
    final account = await GoogleSignIn().signIn();
    if (account == null) return false;
    final idToken = (await account.authentication).idToken;
    if (idToken == null) throw Exception('Google did not return an id token');
    await auth.signInWithGoogle(idToken);
    return true;
  }
}

final obSocialSignInProvider = Provider<ObSocialSignIn>(
  (_) => const ObSocialSignIn(),
);
