import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/features/tour/tour_anchors.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:nuvo/features/tour/tour_engine.dart';
import 'package:nuvo/features/tour/tour_flags.dart';
import 'package:nuvo/features/tour/tour_overlay.dart';
import 'package:nuvo/features/tour/tour_store.dart';

/// A page with a tappable target (the arena race card anchor) and a tappable
/// bystander, under the real [TourStage] — the engine's touch contract in
/// isolation.
class TourStageHarness extends StatelessWidget {
  const TourStageHarness({
    super.key,
    required this.onTarget,
    required this.onOther,
    this.withTarget = true,
    this.reduceMotion = false,
  });

  final VoidCallback onTarget;
  final VoidCallback onOther;
  final bool withTarget;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 40,
              top: 200,
              width: 200,
              height: 90,
              child: withTarget
                  ? GestureDetector(
                      key: TourAnchors.keyOf(TourAnchor.arenaRaceCard),
                      onTap: onTarget,
                      child: const ColoredBox(
                        color: Colors.orange,
                        child: Text('target'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Positioned(
              left: 40,
              top: 520,
              width: 200,
              height: 60,
              child: GestureDetector(
                key: const ValueKey('other'),
                onTap: onOther,
                child: const ColoredBox(
                  color: Colors.green,
                  child: Text('other'),
                ),
              ),
            ),
            Positioned.fill(
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduceMotion),
                  child: const TourStage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Override> tourOverrides(TourStore store) => [
  tourFeatureEnabledProvider.overrideWithValue(true),
  tourStoreProvider.overrideWithValue(store),
];

Future<ProviderContainer> startTour(
  ProviderContainer container, {
  String location = '/arena',
}) async {
  container.read(tourLocationProvider.notifier).state = location;
  await container
      .read(tourControllerProvider.notifier)
      .sync(email: 'a@b.c', graduated: true);
  return container;
}

/// Overrides that put the tour in the running state with an in-memory store
/// (the store is returned so a test can inspect it).
({List<Override> overrides, TourStore store}) runningTour({
  TourStore? store,
  String? beat,
}) {
  final s = store ?? TourStore.memory();
  return (
    store: s,
    overrides: [
      tourFeatureEnabledProvider.overrideWithValue(true),
      tourStoreProvider.overrideWithValue(s),
      tourControllerProvider.overrideWith((ref) {
        final c = TourController(s)..start();
        if (beat != null) c.debugSetBeat(beat);
        return c;
      }),
    ],
  );
}
