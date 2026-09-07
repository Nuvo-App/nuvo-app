import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/race_controller.dart';
import 'motion_session_upload_queue.dart';

/// App-wide singleton upload queue for motion verification sessions. Wired to
/// [raceRepositoryProvider] so a staged artifact uploads with the signed-in
/// user's token; failures stay staged and retry on the next [flush].
final motionSessionUploadQueueProvider = Provider<MotionSessionUploadQueue>((
  ref,
) {
  final repo = ref.watch(raceRepositoryProvider);
  return MotionSessionUploadQueue(
    upload: ({required metadata, required gzipBytes}) =>
        repo.uploadMotionSession(metadata: metadata, gzipBytes: gzipBytes),
  );
});
