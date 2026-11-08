import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/race_models.dart';

/// The single "Submit proof" entry for the v13 shell. Every v13 surface
/// (Arena race cards, nudges, Race detail, Activity "Take it back") calls
/// this, so the proof flow is swapped in exactly one place.
///
/// Stage S5 replaces the body with the v13 Submit proof bottom sheet; until
/// then it opens the existing proof route for that race.
Future<void> openSubmitProof(
  BuildContext context,
  WidgetRef ref,
  Race race,
) async {
  await context.push('/race/${Uri.encodeComponent(race.id)}/proof');
}
