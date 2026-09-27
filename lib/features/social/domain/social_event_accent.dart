import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The Nuvo social color grammar — one accent meaning per event kind, shared
/// by Notifications, Crew activity, and My Nuvo so the three social surfaces
/// read as a single designed system.
///
/// Meanings:
/// - competition (Nuvo blue): actionable race events — invites, joins,
///   start lines, rank movement.
/// - threat (red): a direct competitive hit on the viewer — being passed,
///   losing the lead, rejected proof. Reserved; never decoration.
/// - attention (warm orange): social asks needing the viewer — crew
///   requests, reactions. Also pending/timer urgency.
/// - positive (green): connected, accepted, completed — the feel-good side.
/// - neutral (navy/ink): anything else; no semantic charge.
enum SocialAccent { competition, threat, attention, positive, neutral }

/// Resolve the accent for a notification category or crew-activity event
/// type. Unknown kinds fall back to [SocialAccent.neutral] so new categories
/// render quietly until they get a meaning.
SocialAccent socialAccentFor(String kind) => switch (kind) {
      // Direct competitive threat to the viewer.
      'passed_on_leaderboard' ||
      'proof_rejected' =>
        SocialAccent.threat,

      // Social attention — a request or a reaction aimed at the viewer.
      'crew_request' ||
      'reaction' ||
      'race_starting' =>
        SocialAccent.attention,

      // Positive social/completion state.
      'crew_connected' ||
      'crew_request_accepted' ||
      'proof_accepted' ||
      'race_completed' ||
      'winner_determined' =>
        SocialAccent.positive,

      // Actionable race/competition events.
      'race_invite' ||
      'race_joined' ||
      'race_created' ||
      'race_started' ||
      'rank_changed' ||
      'lead_changed' ||
      'participant_finished' ||
      'personal_best' ||
      'rematch_requested' ||
      'progress_accepted' ||
      'attempt_started' ||
      'attempt_completed' ||
      'race_live' =>
        SocialAccent.competition,

      _ => SocialAccent.neutral,
    };

/// The icon that carries the accent — small marks on avatars/markers, so
/// pick dense glyphs that read at 12-16px.
IconData socialAccentIcon(String kind) => switch (kind) {
      'passed_on_leaderboard' => Icons.trending_down_rounded,
      'proof_rejected' => Icons.cancel_rounded,
      'proof_accepted' => Icons.check_circle_rounded,
      'crew_request' => Icons.person_add_rounded,
      'crew_connected' => Icons.group_rounded,
      'crew_request_accepted' => Icons.handshake_rounded,
      'reaction' => Icons.local_fire_department_rounded,
      'race_starting' => Icons.timer_rounded,
      'race_completed' => Icons.flag_rounded,
      'winner_determined' => Icons.emoji_events_rounded,
      'race_invite' => Icons.mail_rounded,
      'race_joined' || 'race_created' => Icons.group_add_rounded,
      'race_started' => Icons.play_circle_rounded,
      'rank_changed' => Icons.swap_vert_rounded,
      'lead_changed' => Icons.bolt_rounded,
      'participant_finished' => Icons.sports_score_rounded,
      'personal_best' => Icons.star_rounded,
      'rematch_requested' => Icons.replay_rounded,
      _ => Icons.notifications_rounded,
    };

extension SocialAccentRole on SocialAccent {
  /// The color role — surface/border/on/base are theme-aware.
  NuvoColorRole role(BuildContext context) {
    final s = context.semanticColors;
    return switch (this) {
      SocialAccent.competition => s.neutral,
      SocialAccent.threat => s.danger,
      SocialAccent.attention => s.warning,
      SocialAccent.positive => s.success,
      SocialAccent.neutral => _neutralRole(context),
    };
  }

  /// Uncharged events get the page's own structural ink — no semantic color.
  static NuvoColorRole _neutralRole(BuildContext context) {
    final t = context.themeColors;
    return NuvoColorRole(
      base: t.inkMuted,
      shadow: t.inkShadow,
      bright: t.inkMuted,
      surface: t.panelLight,
      border: t.divider,
      on: t.inkMuted,
    );
  }
}
