import '../../features/auth/presentation/auth_controller.dart';

/// Data providers load (cache first, then network) when signed in — and also
/// when offline with the saved user, so a cold open without network still
/// shows the last-known screens instead of nothing.
bool authCanLoad(AuthState s) =>
    s.status == AuthStatus.authenticated ||
    (s.status == AuthStatus.offline && s.user != null);
