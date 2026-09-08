import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pending_destination_store.dart';
import '../domain/nuvo_destination.dart';

/// The single intake for every inbound link: universal links
/// (`https://<host>/j/<token>`), the custom scheme (`nuvo://…`), and — via
/// [handleDestination] — push-notification taps. Each is parsed to one
/// [NuvoDestination] and handed to the one router. Nothing else in the app
/// listens for links.
class DeepLinkController {
  DeepLinkController({AppLinks? appLinks, PendingDestinationStore? pending})
      : _appLinks = appLinks ?? AppLinks(),
        _pending = pending ?? PendingDestinationStore();

  final AppLinks _appLinks;
  final PendingDestinationStore _pending;

  GoRouter? _router;
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Wire up once the router exists. Handles the cold-start link and then
  /// every link while the app runs.
  Future<void> start(GoRouter router) async {
    if (_started) return;
    _started = true;
    _router = router;

    _sub = _appLinks.uriLinkStream.listen(
      _onUri,
      onError: (Object e) => debugPrint('[DeepLink] stream error: $e'),
    );

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _onUri(initial);
    } catch (e) {
      debugPrint('[DeepLink] getInitialLink failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
  }

  void _onUri(Uri uri) {
    final dest = NuvoDestination.tryParse(uri);
    debugPrint('[DeepLink] $uri → ${dest?.runtimeType ?? 'ignored'}');
    if (dest == null) return; // not a Nuvo link — do nothing (never open it)
    handleDestination(dest);
  }

  /// Route to a destination now, or stash it through the auth flow. Shared by
  /// link intake and push-notification taps.
  Future<void> handleDestination(NuvoDestination dest, {bool authed = true}) async {
    final router = _router;
    if (router == null) {
      // Router not ready yet (very early cold start) — stash and let the auth
      // gate pick it up.
      await _pending.put(dest);
      return;
    }
    if (!authed && dest.requiresAuth) {
      await _pending.put(dest);
      router.go('/welcome');
      return;
    }
    router.go(dest.location);
  }
}

final pendingDestinationStoreProvider =
    Provider<PendingDestinationStore>((_) => PendingDestinationStore());

final deepLinkControllerProvider = Provider<DeepLinkController>((ref) {
  final c = DeepLinkController(pending: ref.watch(pendingDestinationStoreProvider));
  ref.onDispose(c.dispose);
  return c;
});
