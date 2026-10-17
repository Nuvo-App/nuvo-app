import 'package:nuvo/core/utils/json_safe.dart';

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
    mode: jStr(json['mode']) ?? 'real',
    headerPulse: jStr(json['headerPulse']) ?? '',
    focusBoard: jMap(json['focusBoard']) != null
        ? ArenaBoard.fromJson(jMap(json['focusBoard'])!)
        : null,
    liveBoards:
        jMapList(json['liveBoards']).map(ArenaBoard.fromJson).toList(),
    activity:
        jMapList(json['activity']).map(ArenaActivity.fromJson).toList(),
    results:
        jMapList(json['results']).map(ArenaBoard.fromJson).toList(),
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
    this.myRank,
    this.chaseCopy,
    this.leaderName,
    this.leaderPhotoUrl,
    this.daysLeft,
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
  final int? myRank;
  final String? chaseCopy;
  final String? leaderName;
  final String? leaderPhotoUrl;
  final int? daysLeft;

  bool get isDemo => source == 'demo';

  factory ArenaBoard.fromJson(Map<String, dynamic> json) => ArenaBoard(
    id: (jStr(json['id']) ?? ''),
    source: jStr(json['source']) ?? 'real',
    title: (jStr(json['title']) ?? ''),
    proofLabel: jStr(json['proofLabel']),
    progressLabel: jStr(json['progressLabel']) ?? '',
    boardContext: jStr(json['boardContext']) ?? '',
    primaryActionLabel: jStr(json['primaryActionLabel']) ?? 'Open board',
    primaryActionType: jStr(json['primaryActionType']) ?? 'open_board',
    progressPercent: jInt(json['progressPercent']),
    racerCount: jInt(json['racerCount']),
    isResult: jBool(json['isResult']) ?? false,
    badgeLabel: jStr(json['badgeLabel']),
    miniLeaderboard:
        jMapList(json['miniLeaderboard']).map(ArenaMiniLeaderboardRow.fromJson).toList(),
    myRank: jInt(json['myRank']),
    chaseCopy: jStr(json['chaseCopy']),
    leaderName: jStr(json['leaderName']),
    leaderPhotoUrl: jStr(json['leaderPhotoUrl']),
    daysLeft: jInt(json['daysLeft']),
  );
}

class ArenaMiniLeaderboardRow {
  const ArenaMiniLeaderboardRow({
    required this.label,
    required this.value,
    this.isCurrentUser = false,
    this.profilePhotoUrl,
  });

  final String label;
  final String value;
  final bool isCurrentUser;
  final String? profilePhotoUrl;

  factory ArenaMiniLeaderboardRow.fromJson(Map<String, dynamic> json) =>
      ArenaMiniLeaderboardRow(
        label: jStr(json['label']) ?? '',
        value: jStr(json['value']) ?? '',
        isCurrentUser: jBool(json['isCurrentUser']) ?? false,
        profilePhotoUrl: jStr(json['profilePhotoUrl']),
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
    id: (jStr(json['id']) ?? ''),
    actorName: jStr(json['actorName']) ?? '',
    text: jStr(json['text']) ?? '',
    raceTitle: jStr(json['raceTitle']),
    timeLabel: jStr(json['timeLabel']) ?? '',
    type: jStr(json['type']) ?? 'proof_submitted',
  );
}
