import '../data/race_models.dart';

class ChaseContext {
  const ChaseContext({
    this.myRank,
    required this.totalCount,
    this.chaseCopy,
    this.leaderName,
    this.leaderPhotoUrl,
    this.leaderGap,
    this.daysLeft,
  });

  final int? myRank;
  final int totalCount;
  final String? chaseCopy;
  final String? leaderName;
  final String? leaderPhotoUrl;
  final int? leaderGap;
  final int? daysLeft;

  static ChaseContext compute(Race race, String userId) {
    final sorted = [...race.participants]
      ..sort((a, b) {
        final rankA = a.rank ?? 9999;
        final rankB = b.rank ?? 9999;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return b.progressValue.compareTo(a.progressValue);
      });

    final myIndex = sorted.indexWhere((p) => p.userId == userId);
    final myRank = myIndex >= 0 ? sorted[myIndex].rank ?? myIndex + 1 : null;
    final total = sorted.length;

    final myPart = race.participantFor(userId);
    final myValue = myPart?.progressValue ?? 0;

    final leader = sorted.isNotEmpty ? sorted.first : null;
    final isLeading = leader?.userId == userId;
    final leaderGap = leader != null && !isLeading
        ? (leader.progressValue - myValue)
        : 0;

    final personAhead = myIndex > 0 ? sorted[myIndex - 1] : null;

    String? chaseCopy;
    if (total <= 1) {
      chaseCopy = 'Set the pace. Invite your crew to chase you.';
    } else if (myRank != null) {
      if (isLeading) {
        final second = sorted.length > 1 ? sorted[1] : null;
        if (second != null) {
          final gap = myValue - second.progressValue;
          final name = _firstName(second.displayName);
          chaseCopy = gap > 0
              ? 'Defend your lead. $name is $gap behind.'
              : 'Tied with $name. Next move wins.';
        }
      } else if (personAhead != null) {
        final gapToPass = personAhead.progressValue - myValue;
        final name = _firstName(personAhead.displayName);
        if (gapToPass <= 0) {
          chaseCopy = 'Tied with $name. Next move wins.';
        } else {
          final targetRank = myRank - 1;
          final oneMove = race.targetValue != null
              ? (race.targetValue! * 0.12).ceil()
              : 10;
          chaseCopy = gapToPass <= oneMove
              ? 'One move beats $name.'
              : 'Beat $name. $gapToPass to take #$targetRank.';
        }
      }
    }

    int? daysLeft;
    if (race.finishLineAt != null) {
      try {
        final finish = DateTime.parse(race.finishLineAt!);
        daysLeft = finish.difference(DateTime.now()).inDays.clamp(0, 9999);
      } catch (_) {}
    }

    return ChaseContext(
      myRank: myRank,
      totalCount: total,
      chaseCopy: chaseCopy,
      leaderName: leader != null && !isLeading
          ? _firstName(leader.displayName)
          : null,
      leaderPhotoUrl: leader != null && !isLeading
          ? leader.profilePhotoUrl
          : null,
      leaderGap: leaderGap > 0 ? leaderGap : null,
      daysLeft: daysLeft,
    );
  }

  static String _firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : name;
  }
}
