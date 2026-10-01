import 'dart:async';
import 'dart:io';

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

/// The shared store-review credential — the canonical App Review identity
/// (the one named in the review notes). It always renders the polished demo
/// world and replays the first-use experience on every cold launch. Other
/// @getnuvo.net accounts are ordinary accounts — this check is an exact
/// match, never a domain match.
bool isNuvoStoreDemoEmail(String email) =>
    email.trim().toLowerCase() == 'testing@getnuvo.net';

/// True when [e] is a transport-level failure — unreachable (ApiException 0),
/// timed out (408 / TimeoutException), or a raw socket/TLS error that escaped
/// before the API could wrap it — rather than a real server rejection. Auth
/// screens must say "check your connection" for these instead of surfacing
/// a provider or credentials error that would mislead the user.
bool isNetworkAuthError(Object e) =>
    e is TimeoutException ||
    e is SocketException ||
    e is HandshakeException ||
    (e is ApiException && (e.statusCode == 0 || e.statusCode == 408));

class AuthState {
  const AuthState({required this.status, this.user, this.error});
  final AuthStatus status;
  final AuthUser? user;
  final String? error;

  /// Eligibility for the post-auth first-race coach guide. This is a property
  /// of the resolved ACCOUNT — the dedicated store-review credential
  /// (testing@getnuvo.net) or any backend-flagged demo account — computed
  /// identically for restore and every sign-in channel. Whether the guide
  /// actually arms is decided at the routing layer (see
  /// firstRaceGuideAllowed), which additionally consults the persisted
  /// per-account completion flag.
  bool get guideFirstRace {
    final user = this.user;
    return user != null &&
        (isNuvoStoreDemoEmail(user.email) || user.isDemo);
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo)
    : super(const AuthState(status: AuthStatus.loading)) {
    _init();
  }

  final AuthRepository _repo;

  /// Runs at the top of [logout], while the stored tokens are still valid —
  /// this is the only moment device-token unregister can authenticate against
  /// the backend. Wired by the app shell to PushService.onSignedOut. Best
  /// effort: failures must never block sign-out.
  Future<void> Function()? beforeSignOut;

  Future<void> _init() async {
    debugPrint('[AuthController] restoring session');
    // Only the cold start owns `loading` (the constructor sets it). A
    // re-restore — Arena's offline retry calls retryRestore() — must never
    // re-publish `loading` over a resolved session: the route guard sends
    // every protected route to /splash while loading, and splash's loading
    // branch is an empty scaffold. That mid-session bounce is the white
    // screen; keeping the current status keeps the retry in place.
    try {
      final result = await _repo.restoreSession();
      debugPrint('[AuthController] restore result: ${result.runtimeType}');
      if (!mounted) return;
      state = switch (result) {
        RestoreOk(:final user) => AuthState(
          status: AuthStatus.authenticated,
          user: user,
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
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<void> signInWithGoogle(String idToken) async {
    final user = await _repo.signInWithGoogle(idToken);
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  Future<void> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async {
    final user = await _repo.signInWithApple(
      idToken,
      fullName: fullName,
      authorizationCode: authorizationCode,
    );
    if (mounted) {
      state = AuthState(status: AuthStatus.authenticated, user: user);
    }
  }

  /// Whether a failed reviewer sign-in may fall back to a fully local demo
  /// session. Debug builds allow it for any reviewer credential so QA works
  /// on networks that block workers.dev. Release builds allow it ONLY for the
  /// dedicated store-review credential — that session is local-only fixture
  /// data with sentinel tokens that can never authenticate a real request, so
  /// the demo works in airplane mode without exposing a passwordless path into
  /// a real account.
  bool _offlineDemoAllowed(String email) {
    final e = email.trim().toLowerCase();
    return kDebugMode || isNuvoStoreDemoEmail(e);
  }

  Future<void> signInReviewer(String email, String password) async {
    try {
      final user = await _repo.signInReviewer(email, password);
      if (mounted) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
      }
    } on ApiException catch (e) {
      // A real rejection (401) means wrong credentials — surface it. Any
      // other ApiException is transport-shaped (0 unreachable, 408 timeout,
      // 5xx), so it takes the same offline fallback as a raw socket error
      // rather than masquerading as bad credentials.
      if (e.statusCode == 401 || !_offlineDemoAllowed(email)) rethrow;
      final user = await _repo.signInOfflineDemo();
      if (mounted) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
      }
    } catch (_) {
      if (!_offlineDemoAllowed(email)) rethrow;
      final user = await _repo.signInOfflineDemo();
      if (mounted) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
      }
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

  Future<void> attestAge() => _repo.attestAge();

  Future<bool> getMotionConsent() async {
    final consent = await _repo.getMotionConsent();
    return consent['consented'] == true;
  }

  Future<void> setMotionConsent({required bool consented}) async {
    await _repo.setMotionConsent(consented: consented);
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
    // Unregister this device's push token BEFORE the token store clears —
    // DeviceApi.unregister needs a still-valid access token to reach the
    // backend. Doing it post-clear silently leaves the row attached to the
    // signed-out account (the next account on this device then inherits it).
    try {
      await beforeSignOut?.call();
    } catch (_) {
      /* best effort — sign-out is never blocked */
    }
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
