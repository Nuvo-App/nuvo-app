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

/// Upload queue for Teach Nuvo diagnostic sessions — the same stage-then-
/// flush mechanics, but staged under `teach_sessions/` and posted to
/// `/teach-sessions` so the Worker indexes them in `motion_teach_sessions`.
final teachSessionUploadQueueProvider = Provider<MotionSessionUploadQueue>((ref) {
  final repo = ref.watch(raceRepositoryProvider);
  return MotionSessionUploadQueue(
    dirName: 'teach_sessions',
    upload: ({required metadata, required gzipBytes}) =>
        repo.uploadTeachSession(metadata: metadata, gzipBytes: gzipBytes),
  );
});
