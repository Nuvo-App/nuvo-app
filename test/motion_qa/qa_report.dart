import 'replay_runner.dart';

/// Generates a confusion/QA report from replay results.
///
/// Output is both machine-readable (JSON) and human-readable (Markdown).
class QaReportGenerator {
  const QaReportGenerator();

  /// Generates a full report for a set of replay results.
  QaReport generate(List<ReplayResult> results, String movementName) {
    final positives = results.where((r) => r.shouldMatch).toList();
    final confusers = results.where((r) => !r.shouldMatch).toList();

    final accepted = positives.where((r) => r.detectedReps >= r.expectedReps).length;
    final rejected = positives.where((r) => r.detectedReps < r.expectedReps).length;

    final falseAccepts = <String, int>{};
    for (final c in confusers) {
      final label = _confuserLabel(c.fixtureId);
      falseAccepts[label] = (falseAccepts[label] ?? 0) + (c.detectedReps > 0 ? 1 : 0);
    }

    final failureReasons = <String, int>{};
    for (final p in positives) {
      if (!p.matched) {
        for (final reason in p.failureReasons) {
          final key = reason.split(':').first;
          failureReasons[key] = (failureReasons[key] ?? 0) + 1;
        }
      }
    }

    final augmentedResults = results.where((r) => r.fixtureId.contains('__')).toList();
    final robustness = <String, RobustnessEntry>{};
    for (final r in augmentedResults) {
      final variant = r.fixtureId.split('__').last;
      final existing = robustness[variant];
      if (existing == null) {
        robustness[variant] = RobustnessEntry(
          variant: variant,
          total: 1,
          correct: r.matched ? 1 : 0,
        );
      } else {
        robustness[variant] = RobustnessEntry(
          variant: variant,
          total: existing.total + 1,
          correct: existing.correct + (r.matched ? 1 : 0),
        );
      }
    }

    return QaReport(
      movement: movementName,
      positiveTotal: positives.length,
      positiveAccepted: accepted,
      positiveRejected: rejected,
      acceptRate: positives.isEmpty ? 0 : accepted / positives.length,
      falseAccepts: falseAccepts,
      failureReasons: failureReasons,
      robustness: robustness.values.toList(),
    );
  }

  String _confuserLabel(String fixtureId) {
    if (fixtureId.contains('squat_confuser')) return 'normal_squat';
    if (fixtureId.contains('jump_confuser')) return 'plain_jump';
    if (fixtureId.contains('jacks_confuser')) return 'jumping_jack';
    if (fixtureId.contains('partial_confuser')) return 'partial_squat';
    return fixtureId;
  }
}

class RobustnessEntry {
  const RobustnessEntry({
    required this.variant,
    required this.total,
    required this.correct,
  });

  final String variant;
  final int total;
  final int correct;

  double get rate => total == 0 ? 0 : correct / total;
}

class QaReport {
  const QaReport({
    required this.movement,
    required this.positiveTotal,
    required this.positiveAccepted,
    required this.positiveRejected,
    required this.acceptRate,
    required this.falseAccepts,
    required this.failureReasons,
    required this.robustness,
  });

  final String movement;
  final int positiveTotal;
  final int positiveAccepted;
  final int positiveRejected;
  final double acceptRate;
  final Map<String, int> falseAccepts;
  final Map<String, int> failureReasons;
  final List<RobustnessEntry> robustness;

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# QA Report: $movement\n');
    buf.writeln('## POSITIVE');
    buf.writeln('- Total sequences: $positiveTotal');
    buf.writeln('- Accepted: $positiveAccepted');
    buf.writeln('- Rejected: $positiveRejected');
    buf.writeln('- Accept rate: ${(acceptRate * 100).toStringAsFixed(1)}%\n');
    buf.writeln('## CONFUSERS');
    for (final e in falseAccepts.entries) {
      buf.writeln('- ${e.key} → false accepts: ${e.value}');
    }
    buf.writeln();
    buf.writeln('## FAILURE REASONS');
    if (failureReasons.isEmpty) {
      buf.writeln('- (none)');
    } else {
      for (final e in failureReasons.entries) {
        buf.writeln('- ${e.key}: ${e.value}');
      }
    }
    buf.writeln();
    buf.writeln('## ROBUSTNESS');
    for (final r in robustness) {
      buf.writeln('- ${r.variant}: ${r.correct}/${r.total} (${(r.rate * 100).toStringAsFixed(1)}%)');
    }
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'movement': movement,
        'positive': {
          'total': positiveTotal,
          'accepted': positiveAccepted,
          'rejected': positiveRejected,
          'acceptRate': acceptRate,
        },
        'falseAccepts': falseAccepts,
        'failureReasons': failureReasons,
        'robustness': robustness.map((r) => {
              'variant': r.variant,
              'total': r.total,
              'correct': r.correct,
              'rate': r.rate,
            }).toList(),
      };
}
