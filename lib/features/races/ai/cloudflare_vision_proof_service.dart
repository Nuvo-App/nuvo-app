import 'package:uuid/uuid.dart';

import '../data/race_repository.dart';
import 'live_proof_models.dart';

class CloudflareVisionProofService {
  CloudflareVisionProofService(this._repository, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final RaceRepository _repository;
  final Uuid _uuid;

  Future<CloudflareVisionLiveProofSignal> analyzeFrame({
    required String raceId,
    required String activityId,
    required String prompt,
    required String imageBase64,
    String imageMimeType = 'image/jpeg',
  }) async {
    final observationId = _uuid.v4();
    final observation = await _repository.analyzeVisionObservation(
      raceId,
      observationId: observationId,
      activityId: activityId,
      prompt: prompt,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );
    return CloudflareVisionLiveProofSignal(
      observationId: observation.observationId,
      prompt: prompt,
      activityDetected: observation.activityDetected,
      actionComplete: observation.actionComplete,
      confidence: observation.confidence,
      summary: observation.summary,
      metadata: {
        'activityId': observation.activityId,
        if (observation.raw != null) 'raw': observation.raw,
      },
    );
  }
}
