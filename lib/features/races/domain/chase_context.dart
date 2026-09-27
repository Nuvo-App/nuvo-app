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
    this.timeLeft,
  });

  final int? myRank;
  final int totalCount;
  final String? chaseCopy;
  final String? leaderName;
  final String? leaderPhotoUrl;
  final int? leaderGap;
  final int? daysLeft;

  /// Compact countdown for deadline races ("3d", "4h", "12m") — derived from
  /// the server's `timeRemainingSeconds`/`serverTime`, never device-clock
  /// guesswork about how much race time is left.
  final String? timeLeft;

  static ChaseContext compute(Race race, String userId) {
    // The server's viewerContext is the canonical competitive read — when the
    // payload carries one, use its rank/gaps/leader instead of recomputing
    // standings locally (single source of race truth).
    final vc = race.viewerContext;
    final lowerIsBetter = race.scoreDirection == 'lower';

    final sorted = [...race.participants]
      ..sort((a, b) {
        final rankA = a.rank ?? 9999;
        final rankB = b.rank ?? 9999;
        if (rankA != rankB) return rankA.compareTo(rankB);
        // Without server ranks: fastest-time races sort ascending (a zero
        // means "hasn't attempted" and ranks last); others descending.
        if (lowerIsBetter) {
          final av = a.progressValue <= 0 ? 1 << 30 : a.progressValue;
          final bv = b.progressValue <= 0 ? 1 << 30 : b.progressValue;
          return av.compareTo(bv);
        }
        return b.progressValue.compareTo(a.progressValue);
      });

    final myIndex = sorted.indexWhere((p) => p.userId == userId);
    final myRank =
        vc?.rank ??
        (myIndex >= 0 ? sorted[myIndex].rank ?? myIndex + 1 : null);
    final total = sorted.length;

    final myPart = race.participantFor(userId);
    final myValue = vc?.viewerScore ?? myPart?.progressValue ?? 0;

    final leader =
        vc?.leaderUserId != null
            ? race.participantFor(vc!.leaderUserId!)
            : (sorted.isNotEmpty ? sorted.first : null);
    final isLeading = vc?.isLeading ?? (leader?.userId == userId);
    final leaderGap =
        vc?.gapToLeader ??
        (leader != null && !isLeading
            ? (lowerIsBetter
                  ? myValue - leader.progressValue
                  : leader.progressValue - myValue)
            : 0);

    final personAhead = myIndex > 0 ? sorted[myIndex - 1] : null;

    String? chaseCopy;
    if (total <= 1) {
      chaseCopy = 'Set the pace. Invite your crew to chase you.';
    } else if (myRank != null) {
      if (isLeading) {
        final second = sorted.length > 1 ? sorted[1] : null;
        if (second != null) {
          final gap = lowerIsBetter
              ? second.progressValue - myValue
              : myValue - second.progressValue;
          final name = _firstName(second.displayName);
          chaseCopy = gap > 0
              ? 'Defend your lead. $name is $gap behind.'
              : 'Tied with $name. Next move wins.';
        }
      } else if (personAhead != null) {
        final gapToPass =
            vc?.gapToNextRank ??
            (lowerIsBetter
                ? myValue - personAhead.progressValue
                : personAhead.progressValue - myValue);
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

    // Deadline math runs off the server clock — device time is display only.
    final serverNow =
        DateTime.tryParse(race.serverTime ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    int? daysLeft;
    String? timeLeft;
    final remainingSeconds = vc?.timeRemainingSeconds;
    if (remainingSeconds != null) {
      timeLeft = _compactCountdown(remainingSeconds);
      daysLeft = (remainingSeconds / 86400).floor().clamp(0, 9999);
    } else if (race.finishLineAt != null) {
      final finish = DateTime.tryParse(race.finishLineAt!);
      if (finish != null) {
        final secs = finish.difference(serverNow).inSeconds.clamp(0, 99999999);
        daysLeft = (secs / 86400).floor();
        timeLeft = _compactCountdown(secs);
      }
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
      timeLeft: timeLeft,
    );
  }

  /// "3d" / "4h" / "12m" / "<1m" — compact deadline countdown.
  static String _compactCountdown(int seconds) {
    if (seconds >= 86400) return '${seconds ~/ 86400}d';
    if (seconds >= 3600) return '${seconds ~/ 3600}h';
    if (seconds >= 60) return '${seconds ~/ 60}m';
    return '<1m';
  }

  static String _firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : name;
  }
}
