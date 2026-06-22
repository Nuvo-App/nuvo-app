class ArenaSnapshot {
  const ArenaSnapshot({
    required this.mode,
    required this.headerPulse,
    this.focusBoard,
    this.liveBoards = const [],
    this.activity = const [],
    this.results = const [],
  });

  final String mode; // 'real' | 'demo'
  final String headerPulse;
  final ArenaBoard? focusBoard;
  final List<ArenaBoard> liveBoards;
  final List<ArenaActivity> activity;
  final List<ArenaBoard> results;

  factory ArenaSnapshot.fromJson(Map<String, dynamic> json) => ArenaSnapshot(
    mode: json['mode'] as String? ?? 'real',
    headerPulse: json['headerPulse'] as String? ?? '',
    focusBoard: json['focusBoard'] != null
        ? ArenaBoard.fromJson(json['focusBoard'] as Map<String, dynamic>)
        : null,
    liveBoards:
        (json['liveBoards'] as List<dynamic>?)
            ?.map((b) => ArenaBoard.fromJson(b as Map<String, dynamic>))
            .toList() ??
        [],
    activity:
        (json['activity'] as List<dynamic>?)
            ?.map((a) => ArenaActivity.fromJson(a as Map<String, dynamic>))
            .toList() ??
        [],
    results:
        (json['results'] as List<dynamic>?)
            ?.map((b) => ArenaBoard.fromJson(b as Map<String, dynamic>))
            .toList() ??
        [],
  );

  bool get isEmpty =>
      focusBoard == null &&
      liveBoards.isEmpty &&
      activity.isEmpty &&
      results.isEmpty;
}

class ArenaBoard {
  const ArenaBoard({
    required this.id,
    required this.source,
    required this.title,
    this.proofLabel,
    required this.progressLabel,
    required this.boardContext,
    required this.primaryActionLabel,
    required this.primaryActionType,
    this.progressPercent,
    this.racerCount,
    required this.isResult,
    this.badgeLabel,
    this.miniLeaderboard = const [],
  });

  final String id;
  final String source; // 'real' | 'demo'
  final String title;
  final String? proofLabel;
  final String progressLabel;
  final String boardContext;
  final String primaryActionLabel;
  final String
  primaryActionType; // 'submit_proof' | 'open_board' | 'start_race' | 'none'
  final int? progressPercent;
  final int? racerCount;
  final bool isResult;
  final String? badgeLabel;
  final List<ArenaMiniLeaderboardRow> miniLeaderboard;

  bool get isDemo => source == 'demo';

  factory ArenaBoard.fromJson(Map<String, dynamic> json) => ArenaBoard(
    id: json['id'] as String,
    source: json['source'] as String? ?? 'real',
    title: json['title'] as String,
    proofLabel: json['proofLabel'] as String?,
    progressLabel: json['progressLabel'] as String? ?? '',
    boardContext: json['boardContext'] as String? ?? '',
    primaryActionLabel: json['primaryActionLabel'] as String? ?? 'Open board',
    primaryActionType: json['primaryActionType'] as String? ?? 'open_board',
    progressPercent: (json['progressPercent'] as num?)?.toInt(),
    racerCount: (json['racerCount'] as num?)?.toInt(),
    isResult: json['isResult'] as bool? ?? false,
    badgeLabel: json['badgeLabel'] as String?,
    miniLeaderboard:
        (json['miniLeaderboard'] as List<dynamic>?)
            ?.map(
              (r) =>
                  ArenaMiniLeaderboardRow.fromJson(r as Map<String, dynamic>),
            )
            .toList() ??
        [],
  );
}

class ArenaMiniLeaderboardRow {
  const ArenaMiniLeaderboardRow({
    required this.label,
    required this.value,
    this.isCurrentUser = false,
  });

  final String label;
  final String value;
  final bool isCurrentUser;

  factory ArenaMiniLeaderboardRow.fromJson(Map<String, dynamic> json) =>
      ArenaMiniLeaderboardRow(
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        isCurrentUser: json['isCurrentUser'] as bool? ?? false,
      );
}

class ArenaActivity {
  const ArenaActivity({
    required this.id,
    required this.actorName,
    required this.text,
    this.raceTitle,
    required this.timeLabel,
    required this.type,
  });

  final String id;
  final String actorName;
  final String text;
  final String? raceTitle;
  final String timeLabel;
  final String
  type; // 'proof_submitted' | 'joined' | 'leader_changed' | 'finished' | 'waiting'

  factory ArenaActivity.fromJson(Map<String, dynamic> json) => ArenaActivity(
    id: json['id'] as String,
    actorName: json['actorName'] as String? ?? '',
    text: json['text'] as String? ?? '',
    raceTitle: json['raceTitle'] as String?,
    timeLabel: json['timeLabel'] as String? ?? '',
    type: json['type'] as String? ?? 'proof_submitted',
  );
}
