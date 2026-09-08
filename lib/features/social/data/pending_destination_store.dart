import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../auth/data/_ls_stub.dart'
    if (dart.library.html) '../../auth/data/_ls_web.dart' as ls;
import '../domain/nuvo_destination.dart';

/// Survives a link → auth → destination flow. When a link (QR, universal link,
/// push) resolves to a destination the logged-out user can't reach yet, the
/// destination's `location` is stashed here, the user goes through sign-in, and
/// the auth gate consumes it exactly once on `authenticated`.
///
/// Non-sensitive (a route string), but stored the same way tokens are so it is
/// available before the widget tree builds and survives a cold start.
class PendingDestinationStore {
  static const _key = 'nuvo_pending_destination';

  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> put(NuvoDestination destination) async {
    final value = destination.location;
    try {
      if (kIsWeb) {
        ls.setItem(_key, value);
      } else {
        await _secure.write(key: _key, value: value);
      }
    } catch (e) {
      debugPrint('[PendingDestination] put failed (${e.runtimeType})');
    }
  }

  /// Read without clearing — used by the auth gate to decide where to land.
  Future<String?> peek() async {
    try {
      return kIsWeb ? ls.getItem(_key) : await _secure.read(key: _key);
    } catch (e) {
      debugPrint('[PendingDestination] peek failed (${e.runtimeType})');
      return null;
    }
  }

  /// Read and clear atomically-ish. Call once, right after the user is
  /// authenticated, then navigate to the returned location.
  Future<String?> consume() async {
    final value = await peek();
    await clear();
    return value;
  }

  Future<void> clear() async {
    try {
      if (kIsWeb) {
        ls.removeItem(_key);
      } else {
        await _secure.delete(key: _key);
      }
    } catch (e) {
      debugPrint('[PendingDestination] clear failed (${e.runtimeType})');
    }
  }
}
