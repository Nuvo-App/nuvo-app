import 'package:flutter/material.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/v13/v13.dart';

// Web placeholder for AiMotionProofScreen.
// Camera and MLKit are mobile-only; this screen is shown on web instead.
class AiMotionProofScreen extends StatelessWidget {
  const AiMotionProofScreen({super.key, required this.raceId});

  final String raceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            V13BackBar(
              title: 'AI Motion Proof',
              onBack: () => safePopOrGo(context, '/race/$raceId/proof'),
            ),
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const V13IconTile(
                    icon: Icons.phone_iphone_rounded,
                    color: V13.sky,
                    size: 64,
                    radius: V13.radiusTileLg,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Camera verification runs\non the mobile app',
                    style: V13.sectionHead,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Use the Nuvo mobile app to verify this movement with the camera.',
                      style: V13.body.copyWith(color: V13.muted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V13.pagePad,
                0,
                V13.pagePad,
                V13.gapLg,
              ),
              child: V13Button.primary(
                label: 'Back to proof',
                icon: Icons.arrow_back_rounded,
                fullWidth: true,
                onPressed: () => safePopOrGo(context, '/race/$raceId/proof'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
