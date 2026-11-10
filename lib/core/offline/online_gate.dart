import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../v13/v13.dart';
import 'reachability.dart';

/// True when Nuvo is reachable and the session isn't in offline mode.
/// Server-only features (camera proof verification, race creation, invites,
/// join-by-code, search) disable themselves while this is false and come
/// back automatically on reconnect.
bool appOnline(WidgetRef ref) =>
    ref.watch(reachabilityProvider).online &&
    ref.watch(authControllerProvider).status != AuthStatus.offline;

/// Same check without subscribing (for tap handlers).
bool appOnlineNow(WidgetRef ref) =>
    ref.read(reachabilityProvider).online &&
    ref.read(authControllerProvider).status != AuthStatus.offline;

/// The one short "needs internet" line shown under a greyed action.
class NeedsInternetLine extends StatelessWidget {
  const NeedsInternetLine({super.key, this.text = 'Needs internet'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: V13.gapSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 14, color: V13.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: V13.caption.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
