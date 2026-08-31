import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Canonical verification outcome for a proof. The server sends a handful of
/// raw strings (`ai_verified`, `accepted`, `ai_failed`, `rejected`,
/// `needs_review`, and occasionally `ai_pending` / `logged` / unknown); this
/// collapses them into four states the UI can reason about — with an explicit
/// [unknown] that is **never** treated as a success.
enum ProofStatus { verified, needsReview, notVerified, pending, unknown }

ProofStatus proofStatusFromRaw(String? raw) => switch (raw) {
  'ai_verified' || 'accepted' || 'verified' => ProofStatus.verified,
  'needs_review' || 'in_review' || 'review' => ProofStatus.needsReview,
  'ai_failed' || 'rejected' || 'failed' => ProofStatus.notVerified,
  'ai_pending' || 'pending' || 'logged' || 'processing' => ProofStatus.pending,
  _ => ProofStatus.unknown,
};

/// How a proof status should read in the UI — one place, one vocabulary.
class ProofStatusPresentation {
  const ProofStatusPresentation({
    required this.status,
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.surface,
    required this.icon,
  });

  final ProofStatus status;

  /// Sentence-style label, e.g. "Camera verified".
  final String label;

  /// Compact label for chips/rows, e.g. "Verified".
  final String shortLabel;

  final Color color;
  final Color surface;
  final IconData icon;

  bool get isVerified => status == ProofStatus.verified;
  bool get isNotVerified => status == ProofStatus.notVerified;
  bool get countsTowardBoard => status == ProofStatus.verified;
}

ProofStatusPresentation proofStatusPresentation(String? raw, {String verb = ''}) {
  final status = proofStatusFromRaw(raw);
  final prefix = verb.isEmpty ? '' : '$verb · ';
  return switch (status) {
    ProofStatus.verified => ProofStatusPresentation(
      status: status,
      label: '${prefix}Camera verified',
      shortLabel: 'Verified',
      color: NuvoColors.success,
      surface: NuvoColors.successSurface,
      icon: Icons.check_circle_rounded,
    ),
    ProofStatus.needsReview => ProofStatusPresentation(
      status: status,
      label: '${prefix}Under review',
      shortLabel: 'Under review',
      color: NuvoColors.warning,
      surface: NuvoColors.warningSurface,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ProofStatus.notVerified => ProofStatusPresentation(
      status: status,
      label: "${prefix}Didn't count",
      shortLabel: 'Not counted',
      color: NuvoColors.danger,
      surface: NuvoColors.dangerSurface,
      icon: Icons.cancel_rounded,
    ),
    ProofStatus.pending => ProofStatusPresentation(
      status: status,
      label: '${prefix}Logged',
      shortLabel: 'Logged',
      color: NuvoColors.muted,
      surface: NuvoColors.panelLight,
      icon: Icons.schedule_rounded,
    ),
    ProofStatus.unknown => ProofStatusPresentation(
      status: status,
      label: '${prefix}Needs review',
      shortLabel: 'Needs review',
      color: NuvoColors.warning,
      surface: NuvoColors.warningSurface,
      icon: Icons.help_outline_rounded,
    ),
  };
}
