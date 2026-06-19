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

    if (authState.status == AuthStatus.loading) return null;
    if (loc == '/splash') return null;

    if (authState.status == AuthStatus.unauthenticated) {
      return _isProtected(loc) ? '/welcome' : null;
    }

    // Authenticated
    final user = authState.user!;
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
      loc.startsWith('/profile') ||
      loc.startsWith('/race/') ||
      loc.startsWith('/races/') ||
      loc.startsWith('/proof/');

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
