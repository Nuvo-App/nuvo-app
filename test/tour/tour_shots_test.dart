// Visual loop: with SHOTS_DIR set, saves PNGs of the tour stage on top of a
// small page at phone sizes; otherwise a plain no-exceptions run.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:nuvo/features/tour/tour_script.dart';
import 'package:nuvo/features/tour/tour_store.dart';
import 'package:nuvo/features/tour/tour_overlay.dart';
import 'package:nuvo/core/v13/widgets/v13_tab_bar.dart';
import 'package:nuvo/features/tour/tour_anchors.dart';
import 'package:nuvo/features/tour/tour_anchors.dart' as a;

import '../helpers/screenshot.dart';
import 'tour_engine_test.dart' show adv;
import 'tour_harness.dart';

Widget _page(Size size) => MaterialApp(
  debugShowCheckedModeBanner: false,
  builder: (context, child) => Stack(
    children: [
      child!,
      const Positioned.fill(child: TourStage()),
    ],
  ),
  home: Scaffold(
    backgroundColor: const Color(0xFFF5F6F8),
    bottomNavigationBar: V13TabBar(
      items: const [
        V13TabItem(label: 'Arena', icon: Icons.stadium),
        V13TabItem(label: 'Compete', icon: Icons.emoji_events),
        V13TabItem(label: 'Crew', icon: Icons.group),
        V13TabItem(label: 'Profile', icon: Icons.person),
      ],
      currentIndex: 0,
      onTap: (_) {},
      slotKeys: [for (var i = 0; i < 4; i++) TourAnchors.dockSlot(i)],
    ),
    body: Stack(
      children: [
        Positioned(
          left: 20,
          right: 20,
          top: 120,
          height: 300,
          child: Container(
            key: TourAnchors.keyOf(a.TourAnchor.arenaRaceCard),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A65),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF07152D), width: 2),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  key: TourAnchors.keyOf(a.TourAnchor.submitProof),
                  height: 52,
                  width: double.infinity,
                  child: const ColoredBox(
                    color: Color(0xFF1264FF),
                    child: Center(child: Text('Submit proof')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  setUpAll(loadShotFonts);
  const sizes = {'390x844': Size(390, 844), '320x568': Size(320, 568)};
  for (final e in sizes.entries) {
    for (final beat in [
      'arenaRace',
      'arenaProof',
      'compete',
      kTourNotifyId,
      kTourDoneBeat,
    ]) {
      testWidgets('shot $beat ${e.key}', (t) async {
        t.view.physicalSize = e.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final c = ProviderContainer(
          overrides: tourOverrides(TourStore.memory()),
        );
        addTearDown(c.dispose);
        await startTour(c);
        c.read(tourControllerProvider.notifier).debugSetBeat(beat);
        await t.pumpWidget(
          UncontrolledProviderScope(container: c, child: _page(e.value)),
        );
        await adv(t, const Duration(milliseconds: 2800));
        await shot(t, 'tour_${beat}_${e.key}');
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
