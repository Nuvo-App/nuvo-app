import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
    _ref = ref;
  }

  late final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authControllerProvider);
    final loc = state.matchedLocation;

    // While auth is being determined, never render protected routes — they
    // would try to access secure storage concurrently with the auth restore
    // and can corrupt the session (race condition on web). Send them to
    // /splash which shows the loading state harmlessly.
    if (authState.status == AuthStatus.loading) {
      final dest = _isProtected(loc) ? '/splash' : null;
      debugPrint('[Router] loading → $loc : redirect=$dest');
      return dest;
    }

    if (loc == '/splash') return null;

    if (authState.status == AuthStatus.unauthenticated) {
      final dest = _isProtected(loc) ? '/welcome' : null;
      debugPrint('[Router] unauthenticated → $loc : redirect=$dest');
      return dest;
    }

    // Authenticated
    final user = authState.user!;
    debugPrint('[Router] authenticated uid=${user.id} → $loc');
    if (user.onboardingComplete) {
      if (_isAuthOrOnboarding(loc)) return '/arena';
    } else {
      if (_isAuthPreOnboarding(loc)) return '/onboarding/create-identity';
    }

    return null;
  }

  // Routes that require authentication
  bool _isProtected(String loc) =>
      loc.startsWith('/arena') ||
      loc.startsWith('/pass') ||
      loc.startsWith('/compete') ||
      loc.startsWith('/move') ||
      loc.startsWith('/profile') ||
      loc.startsWith('/race/') ||
      loc.startsWith('/races/') ||
      loc.startsWith('/proof/') ||
      loc.startsWith('/onboarding/');

  // /welcome and /auth/* — before onboarding begins
  bool _isAuthPreOnboarding(String loc) =>
      loc == '/welcome' || loc.startsWith('/auth/');

  // All pre-app routes
  bool _isAuthOrOnboarding(String loc) =>
      loc == '/welcome' ||
      loc.startsWith('/auth/') ||
      loc.startsWith('/onboarding/');
}

final routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});
