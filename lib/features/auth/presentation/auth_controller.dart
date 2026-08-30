import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_api.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';
import '../data/secure_token_store.dart';

enum AuthStatus {
  loading,
  authenticated,
  unauthenticated,

  /// We hold stored tokens but could not reach the server on launch. The user
  /// is NOT logged out — the splash offers a retry.
  offline,
}

bool isNuvoStoreDemoEmail(String email) =>
    email.trim().toLowerCase() == 'testing@getnuvo.net';

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.guideFirstRace = false,
  });
  final AuthStatus status;
  final AuthUser? user;
  final String? error;
  final bool guideFirstRace;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo)
    : super(const AuthState(status: AuthStatus.loading)) {
    _init();
  }

  final AuthRepository _repo;

  Future<void> _init() async {
    debugPrint('[AuthController] restoring session');
    if (mounted && state.status != AuthStatus.loading) {
      state = const AuthState(status: AuthStatus.loading);
    }
    try {
      final result = await _repo.restoreSession();
      debugPrint('[AuthController] restore result: ${result.runtimeType}');
      if (!mounted) return;
      state = switch (result) {
        RestoreOk(:final user) => AuthState(
          status: AuthStatus.authenticated,
          user: user,
          guideFirstRace: isNuvoStoreDemoEmail(user.email),
        ),
        RestoreNoSession() => const AuthState(
          status: AuthStatus.unauthenticated,
        ),
        // Keep tokens; the splash shows a retry rather than logging out.
        RestoreUnreachable() => const AuthState(status: AuthStatus.offline),
      };
    } catch (e) {
      debugPrint('[AuthController] restore error (${e.runtimeType})');
      // An unexpected error is not proof the session is invalid — treat it as
      // offline so a retry is possible.
      if (mounted) {
        state = const AuthState(status: AuthStatus.offline);
      }
    }
  }

  /// Re-run session restore. Used by the splash "retry" affordance when the
  /// first launch attempt could not reach the server.
  Future<void> retryRestore() => _init();

  Future<void> startEmailAuth(String email) => _repo.startEmailAuth(email);

  Future<void> verifyEmailCode(String email, String code) async {
    final user = await _repo.verifyEmailCode(email, code);
    if (mounted) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        guideFirstRace: true,
      );
    }
  }

  Future<void> signInWithGoogle(String idToken) async {
    final user = await _repo.signInWithGoogle(idToken);
    if (mounted) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        guideFirstRace: true,
      );
    }
  }

  Future<void> signInWithApple(
    String idToken, {
    String? fullName,
  }) async {
    final user = await _repo.signInWithApple(idToken, fullName: fullName);
    if (mounted) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        guideFirstRace: true,
      );
    }
  }

  Future<void> signInReviewer(String email, String password) async {
    final user = await _repo.signInReviewer(email, password);
    if (mounted) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        guideFirstRace: true,
      );
    }
  }

  Future<void> saveProfile({
    String? fullName,
    String? username,
    bool? privateProfile,
  }) async {
    await _repo.saveProfile(
      fullName: fullName,
      username: username,
      privateProfile: privateProfile,
    );
    final user = await _repo.getMe();
    debugPrint('REFRESHED_USER_PHOTO_URL: ${user.profilePhotoUrl}');
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<bool> checkUsername(String username) => _repo.checkUsername(username);

  Future<void> acceptTerms() async {
    await _repo.acceptTerms();
    final user = await _repo.getMe();
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<void> completeOnboarding() async {
    await _repo.completeOnboarding();
    final user = await _repo.getMe();
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  /// Three-step photo upload: get signed URL → upload bytes → save URL to profile.
  /// Storage credentials never leave the backend; the signed URL carries permission.
  Future<void> uploadProfilePhoto(XFile xFile) async {
    final bytes = await xFile.readAsBytes();
    final contentType = xFile.mimeType ?? 'image/jpeg';
    final urls = await _repo.requestPhotoUploadUrl(
      fileName: xFile.name,
      contentType: contentType,
    );
    await _repo.uploadBytesToSignedUrl(urls.uploadUrl, bytes, contentType);
    await _repo.saveProfile(profilePhotoUrl: urls.publicUrl);
    final user = await _repo.getMe();
    debugPrint('REFRESHED_USER_PHOTO_URL: ${user.profilePhotoUrl}');
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<void> removeProfilePhoto() async {
    await _repo.saveProfile(removePhoto: true);
    final user = await _repo.getMe();
    debugPrint('REFRESHED_USER_PHOTO_URL: ${user.profilePhotoUrl}');
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<PassInfo> getMemberPass() => _repo.getMemberPass();

  Future<void> logout() async {
    await _repo.logout();
    if (mounted) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> sessionExpired() async {
    debugPrint('[AuthController] session expired — clearing tokens');
    await _repo.clearSession();
    if (mounted) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    if (mounted) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (_) => SecureTokenStore(),
);

final authApiProvider = Provider<AuthApi>((_) => AuthApi());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(secureTokenStoreProvider),
  );
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authRepositoryProvider));
  },
);
