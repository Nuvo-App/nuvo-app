import '../ai/custom_pose/custom_pose_verifier_spec.dart';
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
    final verifierType = json['verifierType'] as String? ?? 'preset_pose';
    final parsedCustomSpec = _decodeCustomVerifierSpec(json, verifierType);
    return Race(
      id: json['id'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      title: json['title'] as String? ?? '',
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
      verifierSpec: json['verifierSpec'] is Map
          ? Map<String, dynamic>.from(json['verifierSpec'] as Map)
          : null,
      verifierReleaseId: json['verifierReleaseId'] as String?,
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
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
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
      scoreDirection: json['scoreDirection'] as String? ?? 'higher',
      serverTime: json['serverTime'] as String?,
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

  bool get isCustomVerifierRace => verifierType == customPoseVerifierType;

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
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'Nuvo member',
    username: json['username'] as String?,
    memberId: json['memberId'] as String?,
    initials: json['initials'] as String? ?? 'N',
    addedAt: json['addedAt'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    lastActiveAt: DateTime.tryParse(
      json['lastActiveAt'] as String? ?? '',
    )?.toUtc(),
    level: json['level'] as int?,
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
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Nuvo member',
        progressValue: json['progressValue'] as int? ?? 0,
        progressPercent: json['progressPercent'] as int? ?? 0,
        rank: json['rank'] as int?,
        joinedAt: json['joinedAt'] as String? ?? '',
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
        finishedAt: json['finishedAt'] as String?,
        level: json['level'] as int?,
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
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Nuvo member',
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
        rank: json['rank'] as int? ?? 0,
        scoreValue: json['scoreValue'] as int? ?? 0,
        completedAt: json['completedAt'] as String?,
        level: json['level'] as int?,
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
        raceId: json['raceId'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        rank: (json['rank'] as num?)?.toInt(),
        previousRank: (json['previousRank'] as num?)?.toInt(),
        leaderUserId: json['leaderUserId'] as String?,
        leaderScore: (json['leaderScore'] as num?)?.toInt(),
        viewerScore: (json['viewerScore'] as num?)?.toInt(),
        gapToLeader: (json['gapToLeader'] as num?)?.toInt(),
        gapToNextRank: (json['gapToNextRank'] as num?)?.toInt(),
        goalRemaining: (json['goalRemaining'] as num?)?.toInt(),
        timeRemainingSeconds:
            (json['timeRemainingSeconds'] as num?)?.toInt(),
        startsInSeconds: (json['startsInSeconds'] as num?)?.toInt(),
        isLeading: json['isLeading'] as bool? ?? false,
        isTied: json['isTied'] as bool? ?? false,
        isFinished: json['isFinished'] as bool? ?? false,
        isMember: json['isMember'] as bool? ?? false,
        isSpectator: json['isSpectator'] as bool? ?? false,
        attemptsUsed: (json['attemptsUsed'] as num?)?.toInt() ?? 0,
        attemptsRemaining: (json['attemptsRemaining'] as num?)?.toInt(),
        openAttemptId: json['openAttemptId'] as String?,
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
      attemptId: a['id'] as String? ?? '',
      attemptIndex: (a['attemptIndex'] as num?)?.toInt() ?? 0,
      status: a['status'] as String? ?? 'open',
      startedAt: a['startedAt'] as String?,
      deadlineAt: a['deadlineAt'] as String?,
      attemptsUsed: (json['attemptsUsed'] as num?)?.toInt() ?? 0,
      attemptsRemaining: (json['attemptsRemaining'] as num?)?.toInt(),
      serverTime: json['serverTime'] as String?,
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
    raceId: json['raceId'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'active',
    unchanged: json['unchanged'] as bool? ?? false,
    serverTime: json['serverTime'] as String?,
    winnerUserId: json['winnerUserId'] as String?,
    participants:
        (json['participants'] as List<dynamic>?)
            ?.map(
              (p) =>
                  RaceLiveParticipant.fromJson(p as Map<String, dynamic>),
            )
            .toList() ??
        [],
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
        userId: json['userId'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt(),
        finishedAt: json['finishedAt'] as String?,
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
    this.mediaUrl,
    this.rankBefore,
    this.rankAfter,
    this.peoplePassed,
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

  factory RaceProof.fromJson(Map<String, dynamic> json) => RaceProof(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'Nuvo member',
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
    // Never default a missing/unknown status to a success — an absent verdict
    // must surface for review, not silently credit the leaderboard.
    verificationStatus: json['verificationStatus'] as String? ?? 'needs_review',
    verificationSummary: json['verificationSummary'] as String?,
    reviewedBy: json['reviewedBy'] as String?,
    reviewedAt: json['reviewedAt'] as String?,
    createdAt: json['createdAt'] as String? ?? '',
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    mediaUrl: json['mediaUrl'] as String?,
    rankBefore: (json['rankBefore'] as num?)?.toInt(),
    rankAfter: (json['rankAfter'] as num?)?.toInt(),
    peoplePassed: (json['peoplePassed'] as num?)?.toInt(),
  );
}

// ── Race creation prefill ─────────────────────────────────────────────────────

/// Navigation extra for `/races/new`. Known entries (quick starts, "Race
/// {name}", run-it-back) carry a structured [draft] — the title interpreter
/// is only for USER-WRITTEN [idea] text, read once at the name step.
class RaceCreatePrefill {
  const RaceCreatePrefill({this.idea, this.draft, this.withUser});

  /// User-written idea text — interpreted once into a draft by the composer.
  final String? idea;

  /// Structured draft supplied directly — never re-parsed as text.
  final RaceDraft? draft;

  /// Person context for "Race {name}" entries — pulled in when the race
  /// is created.
  final PublicUser? withUser;

  RaceCreatePrefill copyWith({PublicUser? withUser}) => RaceCreatePrefill(
    idea: idea,
    draft: draft,
    withUser: withUser ?? this.withUser,
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
