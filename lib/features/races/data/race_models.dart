import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/core/utils/json_safe.dart';
import '../ai/motion_v2/motion_v2_models.dart';
import '../ai/motion_v2/motion_v2_verifier_runtime.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import '../domain/race_draft.dart';

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
    this.verifierSpec,
    this.verifierReleaseId,
    this.customVerifierSpec,
    this.customMotionV2Spec,
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
    this.scoreDirection = 'higher',
    this.serverTime,
    this.viewerContext,
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

  /// Immutable control-plane verifier specification returned with a race.
  /// Custom pose races use [customVerifierSpec]; preset races may carry a
  /// validated declarative release here.
  final Map<String, dynamic>? verifierSpec;
  final String? verifierReleaseId;
  final CustomPoseVerifierSpec? customVerifierSpec;

  /// Custom races taught through Motion V2 carry the learned spec instead of
  /// the V1 sequence template — the ONNX matcher verifies proof frames.
  final TaughtMotionV2Spec? customMotionV2Spec;
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

  /// 'higher' or 'lower' — whether a bigger score wins the leaderboard.
  final String scoreDirection;

  /// Authoritative server clock from the response — the only clock that
  /// decides starts, deadlines, and eligibility. Device time is display only.
  final String? serverTime;

  /// Structured competitive context for the signed-in viewer, when the race
  /// payload includes one (single-race reads).
  final RaceViewerContext? viewerContext;

  factory Race.fromJson(Map<String, dynamic> json) {
    final verifierType = jStr(json['verifierType']) ?? 'preset_pose';
    final parsedCustomSpec = _decodeCustomVerifierSpec(json, verifierType);
    return Race(
      id: jStr(json['id']) ?? '',
      creatorId: jStr(json['creatorId']) ?? '',
      title: jStr(json['title']) ?? '',
      description: jStr(json['description']),
      category: jStr(json['category']),
      goalType: jStr(json['goalType']) ?? 'manual',
      targetValue: jInt(json['targetValue']),
      unit: jStr(json['unit']),
      aiActivityType: jStr(json['aiActivityType']),
      targetUnit: jStr(json['targetUnit']),
      proofMode: jStr(json['proofMode']),
      activityId:
          jStr(json['activityId']) ?? jStr(json['aiActivityType']),
      metric:
          jStr(json['metric']) ??
          jStr(json['targetUnit']) ??
          jStr(json['unit']),
      format: jStr(json['format']) ?? 'first_to_goal',
      scoringRule: jStr(json['scoringRule']) ?? 'cumulative_sum',
      attemptDurationSeconds: jInt(json['attemptDurationSeconds']),
      attemptLimit: jInt(json['attemptLimit']),
      verificationMethod:
          jStr(json['verificationMethod']) ?? 'camera_pose',
      verifierType: verifierType,
      verifierVersion: jInt(json['verifierVersion']),
      verifierSpec: json['verifierSpec'] is Map
          ? Map<String, dynamic>.from(json['verifierSpec'] as Map)
          : null,
      verifierReleaseId: jStr(json['verifierReleaseId']),
      customVerifierSpec: parsedCustomSpec.spec,
      customMotionV2Spec: parsedCustomSpec.motionV2Spec,
      customActivityName: jStr(json['customActivityName']),
      verifierInvalidReason:
          jStr(json['verifierInvalidReason']) ?? parsedCustomSpec.error,
      timezone: jStr(json['timezone']) ?? 'America/New_York',
      recurrence: jStr(json['recurrence']) ?? 'none',
      status: jStr(json['status']) ?? 'active',
      storedStatus: jStr(json['storedStatus']),
      winnerUserId: jStr(json['winnerUserId']),
      completedAt: jStr(json['completedAt']),
      startLineAt: jStr(json['startLineAt']),
      finishLineAt: jStr(json['finishLineAt']),
      rules: jStr(json['rules']),
      proofRequirement: jStr(json['proofRequirement']) ?? 'manual',
      proofReviewMode: jStr(json['proofReviewMode']) ?? 'auto_accept',
      visibility: jStr(json['visibility']) ?? 'private',
      inviteCode: jStr(json['inviteCode']),
      createdAt: jStr(json['createdAt']) ?? '',
      updatedAt: jStr(json['updatedAt']) ?? '',
      participants:
          jMapList(json['participants']).map(RaceParticipant.fromJson).toList(),
      recentProofs:
          jMapList(json['recentProofs']).map(RaceProof.fromJson).toList(),
      finalStandings:
          jMapList(json['finalStandings']).map(RaceFinalStanding.fromJson).toList(),
      submissionResult: json['submissionResult'] is Map<String, dynamic>
          ? RaceSubmissionResult.fromJson(
              json['submissionResult'] as Map<String, dynamic>,
            )
          : null,
      scoreDirection: jStr(json['scoreDirection']) ?? 'higher',
      serverTime: jStr(json['serverTime']),
      viewerContext: json['viewerContext'] is Map<String, dynamic>
          ? RaceViewerContext.fromJson(
              json['viewerContext'] as Map<String, dynamic>,
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

  bool get isCustomVerifierRace =>
      verifierType == customPoseVerifierType ||
      verifierType == motionV2VerifierType;

  bool get isSupportedAiMotionRace {
    if (isCustomVerifierRace) return false;
    if (!isAiMotionRace) return false;
    // A pinned remote release makes the race camera-verifiable even when the
    // activity has no compiled enum in this build — the resolver performs the
    // authoritative spec/engine checks before a camera session starts.
    if (_hasRemoteVerifierSpec) return true;
    final activity = activityId ?? aiActivityType;
    if (activity == null) return false;
    final type = MotionActivityType.fromBackendValue(activity);
    return type != null && supportedMotionActivityTypes.contains(type);
  }

  /// Whether this race carries a non-native remote verifier release.
  /// Presence is enough here — spec validity is checked at resolve time.
  bool get _hasRemoteVerifierSpec {
    final engine = verifierSpec?['engineType'];
    return engine is String && engine.isNotEmpty && engine != 'native_v1';
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
  const _DecodedCustomVerifierSpec({this.spec, this.motionV2Spec, this.error});

  final CustomPoseVerifierSpec? spec;
  final TaughtMotionV2Spec? motionV2Spec;
  final String? error;
}

_DecodedCustomVerifierSpec _decodeCustomVerifierSpec(
  Map<String, dynamic> json,
  String verifierType,
) {
  if (verifierType == motionV2VerifierType) {
    final rawSpec = json['verifierSpec'];
    if (rawSpec is Map<String, dynamic>) {
      try {
        return _DecodedCustomVerifierSpec(
          motionV2Spec: TaughtMotionV2Spec.fromJson(rawSpec),
        );
      } catch (_) {
        return const _DecodedCustomVerifierSpec(
          error: 'Custom verifier spec is invalid.',
        );
      }
    }
    return const _DecodedCustomVerifierSpec(
      error: 'Custom verifier spec is missing.',
    );
  }
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
    this.lastActiveAt,
    this.level,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? memberId;
  final String initials;
  final String? addedAt;
  final String? profilePhotoUrl;

  /// Server-owned Nuvo Level for identity surfaces — null when the viewer
  /// cannot see this member's full profile.
  final int? level;

  /// Real, server-recorded presence — touched on session restore. Null means
  /// never recorded (older account) or unknown; never fabricated client-side.
  final DateTime? lastActiveAt;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
    id: (jStr(json['id']) ?? ''),
    displayName: jStr(json['displayName']) ?? 'Nuvo member',
    username: jStr(json['username']),
    memberId: jStr(json['memberId']),
    initials: jStr(json['initials']) ?? 'N',
    addedAt: jStr(json['addedAt']),
    profilePhotoUrl: jStr(json['profilePhotoUrl']),
    lastActiveAt: DateTime.tryParse(
      jStr(json['lastActiveAt']) ?? '',
    )?.toUtc(),
    level: jInt(json['level']),
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
    this.finishedAt,
    this.level,
  });

  final String id;
  final String userId;
  final String displayName;
  final int progressValue;
  final int progressPercent;
  final int? rank;
  final String joinedAt;
  final String? profilePhotoUrl;

  /// Server timestamp of the submission that reached the finish line
  /// (first-to-goal only) — the canonical tiebreak order.
  final String? finishedAt;

  /// Nuvo Level — part of this racer's public identity on the board. Null
  /// when the server masks their identity.
  final int? level;

  factory RaceParticipant.fromJson(Map<String, dynamic> json) =>
      RaceParticipant(
        id: jStr(json['id']) ?? '',
        userId: jStr(json['userId']) ?? '',
        displayName: jStr(json['displayName']) ?? 'Nuvo member',
        progressValue: jInt(json['progressValue']) ?? 0,
        progressPercent: jInt(json['progressPercent']) ?? 0,
        rank: jInt(json['rank']),
        joinedAt: jStr(json['joinedAt']) ?? '',
        profilePhotoUrl: jStr(json['profilePhotoUrl']),
        finishedAt: jStr(json['finishedAt']),
        level: jInt(json['level']),
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
    this.level,
  });

  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final int rank;
  final int scoreValue;
  final String? completedAt;

  /// Nuvo Level — same public-identity rule as participants.
  final int? level;

  factory RaceFinalStanding.fromJson(Map<String, dynamic> json) =>
      RaceFinalStanding(
        userId: jStr(json['userId']) ?? '',
        displayName: jStr(json['displayName']) ?? 'Nuvo member',
        profilePhotoUrl: jStr(json['profilePhotoUrl']),
        rank: jInt(json['rank']) ?? 0,
        scoreValue: jInt(json['scoreValue']) ?? 0,
        completedAt: jStr(json['completedAt']),
        level: jInt(json['level']),
      );
}

/// Structured competitive context for the signed-in viewer — the canonical
/// race-engine read the UI renders (rank, gaps, goal/time remaining) instead
/// of recomputing standings locally.
class RaceViewerContext {
  const RaceViewerContext({
    required this.raceId,
    required this.status,
    this.rank,
    this.previousRank,
    this.leaderUserId,
    this.leaderScore,
    this.viewerScore,
    this.gapToLeader,
    this.gapToNextRank,
    this.goalRemaining,
    this.timeRemainingSeconds,
    this.startsInSeconds,
    this.isLeading = false,
    this.isTied = false,
    this.isFinished = false,
    this.isMember = false,
    this.isSpectator = false,
    this.attemptsUsed = 0,
    this.attemptsRemaining,
    this.openAttemptId,
  });

  final String raceId;
  final String status;
  final int? rank;
  final int? previousRank;
  final String? leaderUserId;
  final int? leaderScore;
  final int? viewerScore;
  final int? gapToLeader;
  final int? gapToNextRank;
  final int? goalRemaining;
  final int? timeRemainingSeconds;
  final int? startsInSeconds;
  final bool isLeading;
  final bool isTied;
  final bool isFinished;
  final bool isMember;
  final bool isSpectator;
  final int attemptsUsed;
  final int? attemptsRemaining;
  final String? openAttemptId;

  factory RaceViewerContext.fromJson(Map<String, dynamic> json) =>
      RaceViewerContext(
        raceId: jStr(json['raceId']) ?? '',
        status: jStr(json['status']) ?? 'active',
        rank: jInt(json['rank']),
        previousRank: jInt(json['previousRank']),
        leaderUserId: jStr(json['leaderUserId']),
        leaderScore: jInt(json['leaderScore']),
        viewerScore: jInt(json['viewerScore']),
        gapToLeader: jInt(json['gapToLeader']),
        gapToNextRank: jInt(json['gapToNextRank']),
        goalRemaining: jInt(json['goalRemaining']),
        timeRemainingSeconds:
            jInt(json['timeRemainingSeconds']),
        startsInSeconds: jInt(json['startsInSeconds']),
        isLeading: jBool(json['isLeading']) ?? false,
        isTied: jBool(json['isTied']) ?? false,
        isFinished: jBool(json['isFinished']) ?? false,
        isMember: jBool(json['isMember']) ?? false,
        isSpectator: jBool(json['isSpectator']) ?? false,
        attemptsUsed: jInt(json['attemptsUsed']) ?? 0,
        attemptsRemaining: jInt(json['attemptsRemaining']),
        openAttemptId: jStr(json['openAttemptId']),
      );
}

/// Server response when an attempt is opened for a best-attempt / timed race.
/// `startedAt`/`deadlineAt` are server timestamps — device clocks never decide
/// whether an attempt is still open.
class RaceAttemptResult {
  const RaceAttemptResult({
    required this.attemptId,
    required this.attemptIndex,
    required this.status,
    this.startedAt,
    this.deadlineAt,
    required this.attemptsUsed,
    this.attemptsRemaining,
    this.serverTime,
  });

  final String attemptId;
  final int attemptIndex;
  final String status;
  final String? startedAt;
  final String? deadlineAt;
  final int attemptsUsed;
  final int? attemptsRemaining;
  final String? serverTime;

  factory RaceAttemptResult.fromJson(Map<String, dynamic> json) {
    final a = (json['attempt'] as Map<String, dynamic>?) ?? const {};
    return RaceAttemptResult(
      attemptId: jStr(a['id']) ?? '',
      attemptIndex: jInt(a['attemptIndex']) ?? 0,
      status: jStr(a['status']) ?? 'open',
      startedAt: jStr(a['startedAt']),
      deadlineAt: jStr(a['deadlineAt']),
      attemptsUsed: jInt(json['attemptsUsed']) ?? 0,
      attemptsRemaining: jInt(json['attemptsRemaining']),
      serverTime: jStr(json['serverTime']),
    );
  }
}

/// Compact live poll payload (`GET /races/:id/live`). `unchanged` means the
/// version the client sent still matches — nothing moved, skip re-render.
class RaceLiveState {
  const RaceLiveState({
    required this.raceId,
    required this.version,
    required this.status,
    required this.unchanged,
    this.serverTime,
    this.winnerUserId,
    this.participants = const [],
    this.viewer,
  });

  final String raceId;
  final int version;
  final String status;
  final bool unchanged;
  final String? serverTime;
  final String? winnerUserId;
  final List<RaceLiveParticipant> participants;
  final RaceViewerContext? viewer;

  factory RaceLiveState.fromJson(Map<String, dynamic> json) => RaceLiveState(
    raceId: jStr(json['raceId']) ?? '',
    version: jInt(json['version']) ?? 0,
    status: jStr(json['status']) ?? 'active',
    unchanged: jBool(json['unchanged']) ?? false,
    serverTime: jStr(json['serverTime']),
    winnerUserId: jStr(json['winnerUserId']),
    participants:
        jMapList(json['participants']).map(RaceLiveParticipant.fromJson).toList(),
    viewer: json['viewer'] is Map<String, dynamic>
        ? RaceViewerContext.fromJson(json['viewer'] as Map<String, dynamic>)
        : null,
  );
}

class RaceLiveParticipant {
  const RaceLiveParticipant({
    required this.userId,
    required this.score,
    this.rank,
    this.finishedAt,
  });

  final String userId;
  final int score;
  final int? rank;
  final String? finishedAt;

  factory RaceLiveParticipant.fromJson(Map<String, dynamic> json) =>
      RaceLiveParticipant(
        userId: jStr(json['userId']) ?? '',
        score: jInt(json['score']) ?? 0,
        rank: jInt(json['rank']),
        finishedAt: jStr(json['finishedAt']),
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
        verifiedValue: jInt(json['verifiedValue']) ?? 0,
        previousScore: jInt(json['previousScore']) ?? 0,
        newScore: jInt(json['newScore']) ?? 0,
        previousRank: jInt(json['previousRank']),
        newRank: jInt(json['newRank']),
        peoplePassed: jInt(json['peoplePassed']) ?? 0,
        raceCompleted: jBool(json['raceCompleted']) ?? false,
        winnerUserId: jStr(json['winnerUserId']),
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
    this.mediaUrl,
    this.rankBefore,
    this.rankAfter,
    this.peoplePassed,
    this.vetoedAt,
    this.vetoCount = 0,
    this.vetoState = 'none',
    this.viewerVoted = false,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? profilePhotoUrl;
  final String? thumbnailUrl;

  /// Participant-only evidence path (`/races/:id/proof-media/object/…`) — the
  /// Worker only emits it to active members; fetch needs the Bearer header.
  final String? mediaUrl;
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

  /// Community veto — 'none' | 'disputed' | 'vetoed'. A vetoed proof stays
  /// visible for audit but no longer counts toward the leaderboard.
  final String? vetoedAt;
  final int vetoCount;
  final String vetoState;
  final bool viewerVoted;

  factory RaceProof.fromJson(Map<String, dynamic> json) => RaceProof(
    id: jStr(json['id']) ?? '',
    userId: jStr(json['userId']) ?? '',
    displayName: jStr(json['displayName']) ?? 'Nuvo member',
    proofType: jStr(json['proofType']) ?? 'manual',
    aiActivityType: jStr(json['aiActivityType']),
    note: jStr(json['note']),
    value: jInt(json['value']),
    detectedValue: jInt(json['detectedValue']),
    targetValue: jInt(json['targetValue']),
    confidence: jDouble(json['confidence']),
    validatorVersion: jStr(json['validatorVersion']),
    framesAnalyzed: jInt(json['framesAnalyzed']),
    validPoseFrames: jInt(json['validPoseFrames']),
    durationMs: jInt(json['durationMs']),
    // Never default a missing/unknown status to a success — an absent verdict
    // must surface for review, not silently credit the leaderboard.
    verificationStatus: jStr(json['verificationStatus']) ?? 'needs_review',
    verificationSummary: jStr(json['verificationSummary']),
    reviewedBy: jStr(json['reviewedBy']),
    reviewedAt: jStr(json['reviewedAt']),
    createdAt: jStr(json['createdAt']) ?? '',
    profilePhotoUrl: jStr(json['profilePhotoUrl']),
    thumbnailUrl: jStr(json['thumbnailUrl']),
    mediaUrl: jStr(json['mediaUrl']),
    rankBefore: jInt(json['rankBefore']),
    rankAfter: jInt(json['rankAfter']),
    peoplePassed: jInt(json['peoplePassed']),
    vetoedAt: jStr(json['vetoedAt']),
    vetoCount: jInt(json['vetoCount']) ?? 0,
    vetoState: jStr(json['vetoState']) ?? 'none',
    viewerVoted: jBool(json['viewerVoted']) ?? false,
  );
}

/// Server outcome of a proof veto — the server owns consensus; the client
/// only renders what it returns.
class ProofVetoResult {
  const ProofVetoResult({
    required this.proofId,
    required this.state,
    required this.vetoCount,
    required this.eligibleVoters,
    required this.threshold,
    required this.alreadyVoted,
  });

  final String proofId;

  /// 'none' | 'disputed' | 'vetoed'.
  final String state;
  final int vetoCount;
  final int eligibleVoters;
  final int threshold;
  final bool alreadyVoted;

  bool get vetoed => state == 'vetoed';

  factory ProofVetoResult.fromJson(Map<String, dynamic> json) =>
      ProofVetoResult(
        proofId: jStr(json['proofId']) ?? '',
        state: jStr(json['state']) ?? 'none',
        vetoCount: jInt(json['vetoCount']) ?? 0,
        eligibleVoters: jInt(json['eligibleVoters']) ?? 0,
        threshold: jInt(json['threshold']) ?? 0,
        alreadyVoted: jBool(json['alreadyVoted']) ?? false,
      );
}

// ── Race creation prefill ─────────────────────────────────────────────────────

/// Navigation extra for `/races/new`. Known entries (quick starts, "Race
/// {name}", run-it-back) carry a structured [draft] — the title interpreter
/// is only for USER-WRITTEN [idea] text, read once at the name step.
class RaceCreatePrefill {
  const RaceCreatePrefill({this.idea, this.draft, this.withUser, this.crewId, this.crewName});

  /// User-written idea text — interpreted once into a draft by the composer.
  final String? idea;

  /// Structured draft supplied directly — never re-parsed as text.
  final RaceDraft? draft;

  /// Person context for "Race {name}" entries — pulled in when the race
  /// is created.
  final PublicUser? withUser;

  /// Crew context — the race was started from inside this crew, so the
  /// composer skips the solo/crew question and links the race to the crew
  /// once it exists.
  final String? crewId;
  final String? crewName;

  RaceCreatePrefill copyWith({PublicUser? withUser}) => RaceCreatePrefill(
    idea: idea,
    draft: draft,
    withUser: withUser ?? this.withUser,
    crewId: crewId,
    crewName: crewName,
  );

  static RaceDraft _presetDraft(MotionActivityType type, int target) =>
      draftForActivity(
        motionActivityForType(type)!,
      ).copyWith(targetValue: target);

  static final pushups = RaceCreatePrefill(
    draft: _presetDraft(MotionActivityType.pushUps, 100),
  );
  static final squats = RaceCreatePrefill(
    draft: _presetDraft(MotionActivityType.squats, 15),
  );
  static final jumpingJacks = RaceCreatePrefill(
    draft: _presetDraft(MotionActivityType.jumpingJacks, 500),
  );
  static final lunges = RaceCreatePrefill(
    draft: _presetDraft(MotionActivityType.lunges, 40),
  );
  static final plank = RaceCreatePrefill(
    draft: _presetDraft(MotionActivityType.plankHold, 300),
  );
}

/// Builds a structured creation draft from a race's canonical fields —
/// run-it-back/clone paths must carry fields, never re-interpret the title.
RaceCreatePrefill prefillFromRace(Race race, {PublicUser? withUser}) {
  final activity = motionActivityForBackendValue(race.effectiveAiActivityType);
  if (activity == null) {
    return RaceCreatePrefill(
      draft: RaceDraft(
        title: race.displayTitle,
        hasCustomName: true,
        activity: motionActivityDefinitions.first,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: race.targetValue ?? 1,
      ),
      withUser: withUser,
    );
  }
  final stored = RaceFormat.fromBackendValue(race.format);
  return RaceCreatePrefill(
    draft: draftForActivity(activity).copyWith(
      title: race.displayTitle,
      hasCustomName: true,
      targetValue: race.targetValue ?? activity.defaultTarget,
      format: stored != null && activity.supportedFormats.contains(stored)
          ? stored
          : null,
    ),
    withUser: withUser,
  );
}
