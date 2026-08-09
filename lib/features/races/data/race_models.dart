import '../ai/custom_pose/custom_pose_verifier_spec.dart';

class Race {
  const Race({
    required this.id,
    required this.creatorId,
    required this.title,
    this.description,
    this.category,
    required this.goalType,
    this.targetValue,
    this.unit,
    this.aiActivityType,
    this.targetUnit,
    this.proofMode,
    this.activityId,
    this.metric,
    this.format = 'first_to_goal',
    this.scoringRule = 'cumulative_sum',
    this.attemptDurationSeconds,
    this.attemptLimit,
    this.verificationMethod = 'camera_pose',
    this.verifierType = 'preset_pose',
    this.verifierVersion,
    this.customVerifierSpec,
    this.customActivityName,
    this.verifierInvalidReason,
    this.timezone = 'America/New_York',
    this.recurrence = 'none',
    required this.status,
    this.storedStatus,
    this.winnerUserId,
    this.completedAt,
    this.startLineAt,
    this.finishLineAt,
    this.rules,
    this.proofRequirement = 'manual',
    this.proofReviewMode = 'auto_accept',
    this.visibility = 'private',
    this.inviteCode,
    required this.createdAt,
    required this.updatedAt,
    this.participants = const [],
    this.recentProofs = const [],
    this.finalStandings = const [],
    this.submissionResult,
  });

  final String id;
  final String creatorId;
  final String title;
  final String? description;
  final String? category;
  final String goalType;
  final int? targetValue;
  final String? unit;
  final String? aiActivityType;
  final String? targetUnit;
  final String? proofMode;
  final String? activityId;
  final String? metric;
  final String format;
  final String scoringRule;
  final int? attemptDurationSeconds;
  final int? attemptLimit;
  final String verificationMethod;
  final String verifierType;
  final int? verifierVersion;
  final CustomPoseVerifierSpec? customVerifierSpec;
  final String? customActivityName;
  final String? verifierInvalidReason;
  final String timezone;
  final String recurrence;
  final String status;
  final String? storedStatus;
  final String? winnerUserId;
  final String? completedAt;
  final String? startLineAt;
  final String? finishLineAt;
  final String? rules;
  final String proofRequirement;
  final String proofReviewMode;
  final String visibility;
  final String? inviteCode;
  final String createdAt;
  final String updatedAt;
  final List<RaceParticipant> participants;
  final List<RaceProof> recentProofs;
  final List<RaceFinalStanding> finalStandings;
  final RaceSubmissionResult? submissionResult;

  factory Race.fromJson(Map<String, dynamic> json) {
    final verifierType = json['verifierType'] as String? ?? 'preset_pose';
    final parsedCustomSpec = _decodeCustomVerifierSpec(json, verifierType);
    return Race(
      id: json['id'] as String,
      creatorId: json['creatorId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String?,
      goalType: json['goalType'] as String? ?? 'manual',
      targetValue: json['targetValue'] as int?,
      unit: json['unit'] as String?,
      aiActivityType: json['aiActivityType'] as String?,
      targetUnit: json['targetUnit'] as String?,
      proofMode: json['proofMode'] as String?,
      activityId:
          json['activityId'] as String? ?? json['aiActivityType'] as String?,
      metric:
          json['metric'] as String? ??
          json['targetUnit'] as String? ??
          json['unit'] as String?,
      format: json['format'] as String? ?? 'first_to_goal',
      scoringRule: json['scoringRule'] as String? ?? 'cumulative_sum',
      attemptDurationSeconds: json['attemptDurationSeconds'] as int?,
      attemptLimit: json['attemptLimit'] as int?,
      verificationMethod:
          json['verificationMethod'] as String? ?? 'camera_pose',
      verifierType: verifierType,
      verifierVersion: json['verifierVersion'] as int?,
      customVerifierSpec: parsedCustomSpec.spec,
      customActivityName: json['customActivityName'] as String?,
      verifierInvalidReason:
          json['verifierInvalidReason'] as String? ?? parsedCustomSpec.error,
      timezone: json['timezone'] as String? ?? 'America/New_York',
      recurrence: json['recurrence'] as String? ?? 'none',
      status: json['status'] as String? ?? 'active',
      storedStatus: json['storedStatus'] as String?,
      winnerUserId: json['winnerUserId'] as String?,
      completedAt: json['completedAt'] as String?,
      startLineAt: json['startLineAt'] as String?,
      finishLineAt: json['finishLineAt'] as String?,
      rules: json['rules'] as String?,
      proofRequirement: json['proofRequirement'] as String? ?? 'manual',
      proofReviewMode: json['proofReviewMode'] as String? ?? 'auto_accept',
      visibility: json['visibility'] as String? ?? 'private',
      inviteCode: json['inviteCode'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      participants:
          (json['participants'] as List<dynamic>?)
              ?.map((p) => RaceParticipant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      recentProofs:
          (json['recentProofs'] as List<dynamic>?)
              ?.map((p) => RaceProof.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      finalStandings:
          (json['finalStandings'] as List<dynamic>?)
              ?.map(
                (p) => RaceFinalStanding.fromJson(p as Map<String, dynamic>),
              )
              .toList() ??
          [],
      submissionResult: json['submissionResult'] is Map<String, dynamic>
          ? RaceSubmissionResult.fromJson(
              json['submissionResult'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  int get participantCount => participants.length;

  bool get isAiMotionRace =>
      proofRequirement == 'ai_check' ||
      proofMode == 'ai_check' ||
      verificationMethod == 'camera_pose' ||
      verificationMethod == 'ai';

  bool get isCustomVerifierRace => verifierType == customPoseVerifierType;

  bool get isSupportedAiMotionRace {
    if (isCustomVerifierRace) return false;
    const supported = {
      'push_ups',
      'jumping_jacks',
      'squats',
      'lunges',
      'plank_hold',
      'high_knees',
      'arm_raises',
    };
    final activity = activityId ?? aiActivityType;
    return isAiMotionRace && activity != null && supported.contains(activity);
  }

  String get effectiveAiActivityType {
    if (activityId != null && activityId!.isNotEmpty) {
      return activityId!;
    }
    if (aiActivityType != null && aiActivityType!.isNotEmpty) {
      return aiActivityType!;
    }
    return '';
  }

  String get displayTitle => title
      .trim()
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');

  RaceParticipant? participantFor(String userId) =>
      participants.where((p) => p.userId == userId).firstOrNull;

  bool isCreator(String userId) => creatorId == userId;

  bool isParticipant(String userId) =>
      participants.any((participant) => participant.userId == userId);
}

class _DecodedCustomVerifierSpec {
  const _DecodedCustomVerifierSpec({this.spec, this.error});

  final CustomPoseVerifierSpec? spec;
  final String? error;
}

_DecodedCustomVerifierSpec _decodeCustomVerifierSpec(
  Map<String, dynamic> json,
  String verifierType,
) {
  if (verifierType != customPoseVerifierType) {
    return const _DecodedCustomVerifierSpec();
  }
  final rawSpec = json['verifierSpec'];
  if (rawSpec == null) {
    return const _DecodedCustomVerifierSpec(
      error: 'Custom verifier spec is missing.',
    );
  }
  if (rawSpec is! Map<String, dynamic>) {
    return const _DecodedCustomVerifierSpec(
      error: 'Custom verifier spec is invalid.',
    );
  }
  try {
    return _DecodedCustomVerifierSpec(
      spec: CustomPoseVerifierSpec.fromJson(rawSpec),
    );
  } catch (_) {
    return const _DecodedCustomVerifierSpec(
      error: 'Custom verifier spec is invalid.',
    );
  }
}

class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    this.username,
    this.memberId,
    required this.initials,
    this.addedAt,
    this.profilePhotoUrl,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? memberId;
  final String initials;
  final String? addedAt;
  final String? profilePhotoUrl;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'Nuvo member',
    username: json['username'] as String?,
    memberId: json['memberId'] as String?,
    initials: json['initials'] as String? ?? 'N',
    addedAt: json['addedAt'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
  );

  String get handleLine {
    final parts = <String>[];
    if (username != null && username!.isNotEmpty) {
      parts.add('@$username');
    }
    if (memberId != null && memberId!.isNotEmpty) {
      parts.add(memberId!);
    }
    return parts.isEmpty ? 'Nuvo member' : parts.join(' / ');
  }
}

class RaceParticipant {
  const RaceParticipant({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.progressValue,
    required this.progressPercent,
    this.rank,
    required this.joinedAt,
    this.profilePhotoUrl,
  });

  final String id;
  final String userId;
  final String displayName;
  final int progressValue;
  final int progressPercent;
  final int? rank;
  final String joinedAt;
  final String? profilePhotoUrl;

  factory RaceParticipant.fromJson(Map<String, dynamic> json) =>
      RaceParticipant(
        id: json['id'] as String,
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? 'Unknown',
        progressValue: json['progressValue'] as int? ?? 0,
        progressPercent: json['progressPercent'] as int? ?? 0,
        rank: json['rank'] as int?,
        joinedAt: json['joinedAt'] as String,
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
      );
}

class RaceFinalStanding {
  const RaceFinalStanding({
    required this.userId,
    required this.displayName,
    this.profilePhotoUrl,
    required this.rank,
    required this.scoreValue,
    this.completedAt,
  });

  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final int rank;
  final int scoreValue;
  final String? completedAt;

  factory RaceFinalStanding.fromJson(Map<String, dynamic> json) =>
      RaceFinalStanding(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? 'Unknown',
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
        rank: json['rank'] as int? ?? 0,
        scoreValue: json['scoreValue'] as int? ?? 0,
        completedAt: json['completedAt'] as String?,
      );
}

class RaceSubmissionResult {
  const RaceSubmissionResult({
    required this.verifiedValue,
    required this.previousScore,
    required this.newScore,
    this.previousRank,
    this.newRank,
    required this.peoplePassed,
    required this.raceCompleted,
    this.winnerUserId,
  });

  final int verifiedValue;
  final int previousScore;
  final int newScore;
  final int? previousRank;
  final int? newRank;
  final int peoplePassed;
  final bool raceCompleted;
  final String? winnerUserId;

  factory RaceSubmissionResult.fromJson(Map<String, dynamic> json) =>
      RaceSubmissionResult(
        verifiedValue: json['verifiedValue'] as int? ?? 0,
        previousScore: json['previousScore'] as int? ?? 0,
        newScore: json['newScore'] as int? ?? 0,
        previousRank: json['previousRank'] as int?,
        newRank: json['newRank'] as int?,
        peoplePassed: json['peoplePassed'] as int? ?? 0,
        raceCompleted: json['raceCompleted'] as bool? ?? false,
        winnerUserId: json['winnerUserId'] as String?,
      );
}

class RaceProof {
  const RaceProof({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.proofType,
    this.aiActivityType,
    this.note,
    this.value,
    this.detectedValue,
    this.targetValue,
    this.confidence,
    this.validatorVersion,
    this.framesAnalyzed,
    this.validPoseFrames,
    this.durationMs,
    required this.verificationStatus,
    this.verificationSummary,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    this.profilePhotoUrl,
    this.thumbnailUrl,
    this.rankBefore,
    this.rankAfter,
    this.peoplePassed,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final String? thumbnailUrl;
  final String proofType;
  final String? aiActivityType;
  final String? note;
  final int? value;
  final int? detectedValue;
  final int? targetValue;
  final double? confidence;
  final String? validatorVersion;
  final int? framesAnalyzed;
  final int? validPoseFrames;
  final int? durationMs;
  final String verificationStatus;
  final String? verificationSummary;
  final String? reviewedBy;
  final String? reviewedAt;
  final String createdAt;
  final int? rankBefore;
  final int? rankAfter;
  final int? peoplePassed;

  factory RaceProof.fromJson(Map<String, dynamic> json) => RaceProof(
    id: json['id'] as String,
    userId: json['userId'] as String,
    displayName: json['displayName'] as String? ?? 'Unknown',
    proofType: json['proofType'] as String? ?? 'manual',
    aiActivityType: json['aiActivityType'] as String?,
    note: json['note'] as String?,
    value: json['value'] as int?,
    detectedValue: json['detectedValue'] as int?,
    targetValue: json['targetValue'] as int?,
    confidence: (json['confidence'] as num?)?.toDouble(),
    validatorVersion: json['validatorVersion'] as String?,
    framesAnalyzed: json['framesAnalyzed'] as int?,
    validPoseFrames: json['validPoseFrames'] as int?,
    durationMs: json['durationMs'] as int?,
    verificationStatus: json['verificationStatus'] as String? ?? 'accepted',
    verificationSummary: json['verificationSummary'] as String?,
    reviewedBy: json['reviewedBy'] as String?,
    reviewedAt: json['reviewedAt'] as String?,
    createdAt: json['createdAt'] as String,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    rankBefore: (json['rankBefore'] as num?)?.toInt(),
    rankAfter: (json['rankAfter'] as num?)?.toInt(),
    peoplePassed: (json['peoplePassed'] as num?)?.toInt(),
  );
}
