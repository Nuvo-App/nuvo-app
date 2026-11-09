import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/v13/v13.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';

/// R4 gate: the fake-data pill exists for testing@getnuvo.net and nobody else.
bool showFakeDataPill(String? email) => isNuvoStoreDemoEmail(email ?? '');

/// R4 — testing@getnuvo.net only: flips fake (presentation) data on/off from
/// any tab and reloads, so the store-review account starts clean but can
/// show a full app on demand.
class FakeDataPill extends ConsumerStatefulWidget {
  const FakeDataPill();

  @override
  ConsumerState<FakeDataPill> createState() => FakeDataPillState();
}

class FakeDataPillState extends ConsumerState<FakeDataPill> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final on = !presentationModeToggleEnabled;
      await setPresentationModeEnabled(on);
      final races = ref.read(raceControllerProvider.notifier)..clearRaces();
      final arena = ref.read(arenaControllerProvider.notifier)..clearSnapshot();
      await Future.wait([
        races.loadRaces(force: true),
        arena.loadSnapshot(force: true),
      ]);
      if (mounted) {
        showV13Toast(context, on ? 'Fake data on.' : 'Fake data off.');
      }
    } catch (_) {
      if (mounted) {
        showV13Toast(context, 'Couldn\u2019t switch data. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = presentationModeToggleEnabled;
    return V13Pressable(
      onTap: _toggle,
      shadow: V13.shadow3,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      semanticLabel: on ? 'Turn fake data off' : 'Load fake data',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? V13.sun : V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(
          _busy ? '\u2026' : (on ? 'Fake data: on' : 'Fake data'),
          style: V13.caption.copyWith(
            color: V13.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Root layer (above the Navigator, so it follows the account onto every
/// screen incl. pushed full-screen routes). Renders nothing for anyone but
/// testing@getnuvo.net.
class FakeDataPillLayer extends ConsumerWidget {
  const FakeDataPillLayer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = showFakeDataPill(
      ref.watch(authControllerProvider).user?.email,
    );
    if (!show) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                opaque: false,
                builder: (_) => SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 12),
                      child: const FakeDataPill(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
