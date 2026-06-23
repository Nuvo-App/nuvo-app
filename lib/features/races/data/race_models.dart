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
    required this.status,
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
  final String status;
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

  factory Race.fromJson(Map<String, dynamic> json) => Race(
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
    status: json['status'] as String? ?? 'active',
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
  );

  int get participantCount => participants.length;

  bool get isAiMotionRace =>
      proofRequirement == 'ai_check' || proofMode == 'ai_check';

  bool get isSupportedAiMotionRace {
    const supported = {
      'jumping_jacks',
      'squats',
      'high_knees',
      'arm_raises',
      'plank_hold',
    };
    final activity = aiActivityType;
    if (activity != null) return isAiMotionRace && supported.contains(activity);

    final normalizedTitle = title.toLowerCase();
    final normalizedUnit = unit?.toLowerCase() ?? '';
    return isAiMotionRace &&
        (normalizedTitle.contains('jumping jack') ||
            normalizedUnit.contains('jumping jack'));
  }

  String get effectiveAiActivityType {
    if (aiActivityType != null && aiActivityType!.isNotEmpty) {
      return aiActivityType!;
    }
    return 'jumping_jacks';
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
    required this.joinedAt,
    this.profilePhotoUrl,
  });

  final String id;
  final String userId;
  final String displayName;
  final int progressValue;
  final int progressPercent;
  final String joinedAt;
  final String? profilePhotoUrl;

  factory RaceParticipant.fromJson(Map<String, dynamic> json) =>
      RaceParticipant(
        id: json['id'] as String,
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? 'Unknown',
        progressValue: json['progressValue'] as int? ?? 0,
        progressPercent: json['progressPercent'] as int? ?? 0,
        joinedAt: json['joinedAt'] as String,
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
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
