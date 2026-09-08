// The one canonical destination model for the whole social platform.
//
// A QR scan, a universal link, a push-notification tap, an in-app notification
// tap, a shared URL and a cold-start pending route ALL resolve to one of these,
// and one router (`NuvoDestination.location`) turns it into a go_router path.
// Nothing navigates on its own — see docs/agents/19-social-platform-contract.md.

import 'package:flutter/foundation.dart';

@immutable
sealed class NuvoDestination {
  const NuvoDestination();

  /// The go_router location this destination maps to. This is the ONLY place
  /// a destination becomes a route string.
  String get location;

  /// True if the app must have an authenticated user before this can render.
  bool get requiresAuth => true;

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Parse an inbound link — a universal link (`https://<host>/j/<token>`),
  /// the custom scheme (`nuvo://j/<token>`), or an in-app path
  /// (`/race/:id`, `/profile/:id`, …). Returns null if it isn't a Nuvo link.
  static NuvoDestination? tryParse(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // nuvo://j/<token>  — the host carries the "j"
    if (uri.scheme == 'nuvo' && uri.host == 'j' && segments.isNotEmpty) {
      return InviteDestination(segments.first);
    }
    // https://<host>/j/<token>  or  nuvo://host/j/<token>
    if (segments.length >= 2 && segments[0] == 'j') {
      return InviteDestination(segments[1]);
    }
    if (segments.isEmpty) return null;

    switch (segments[0]) {
      case 'invite' when segments.length >= 2:
        return InviteDestination(segments[1]);
      case 'race' when segments.length >= 2:
        return RaceDestination(
          segments[1],
          context: segments.length >= 3 ? segments[2] : null,
        );
      case 'profile' when segments.length >= 2:
        return ProfileDestination(segments[1]);
      case 'pass':
        return const CrewDestination();
      case 'crew':
        return const CrewDestination();
      case 'notifications':
        return const NotificationsDestination();
      default:
        return null;
    }
  }

  /// Build a destination from a server-provided structured descriptor
  /// (`{ "type": "race", "id": "...", "context": "leaderboard" }`) — used by
  /// notification payloads and invite-accept responses. The backend never
  /// sends a raw route string; the client owns route construction.
  static NuvoDestination? fromDescriptor(Map<String, dynamic>? d) {
    if (d == null) return null;
    final type = d['type'] as String?;
    final id = (d['id'] ?? d['token']) as String?;
    final ctx = d['context'] as String?;
    switch (type) {
      case 'race' when id != null:
        return RaceDestination(id, context: ctx);
      case 'profile' when id != null:
        return ProfileDestination(id);
      case 'invite' when id != null:
        return InviteDestination(id);
      case 'crew':
        return const CrewDestination();
      case 'notifications':
        return const NotificationsDestination();
      default:
        return null;
    }
  }
}

class RaceDestination extends NuvoDestination {
  const RaceDestination(this.raceId, {this.context});

  final String raceId;

  /// Optional sub-context ('leaderboard', 'review', …). The client decides how
  /// to honour it; unknown values are ignored.
  final String? context;

  @override
  String get location {
    switch (context) {
      case 'review':
        return '/race/$raceId/settings';
      default:
        return '/race/$raceId';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RaceDestination && other.raceId == raceId && other.context == context;
  @override
  int get hashCode => Object.hash(raceId, context);
}

class ProfileDestination extends NuvoDestination {
  const ProfileDestination(this.userId);

  final String userId;

  // A public "view this person" screen arrives with the crew phase (D). Until
  // then a profile destination lands on the people surface — the userId is
  // preserved on the object for when that screen exists.
  @override
  String get location => '/pass?user=$userId';

  @override
  bool operator ==(Object other) => other is ProfileDestination && other.userId == userId;
  @override
  int get hashCode => userId.hashCode;
}

class CrewDestination extends NuvoDestination {
  const CrewDestination();

  @override
  String get location => '/pass';

  @override
  bool operator ==(Object other) => other is CrewDestination;
  @override
  int get hashCode => 0x0c0e;
}

class InviteDestination extends NuvoDestination {
  const InviteDestination(this.token);

  final String token;

  /// The invite screen previews before it does anything, so it does NOT itself
  /// require auth — but accepting does. `/invite/:token` renders logged-out.
  @override
  bool get requiresAuth => false;

  @override
  String get location => '/invite/$token';

  @override
  bool operator ==(Object other) => other is InviteDestination && other.token == token;
  @override
  int get hashCode => token.hashCode;
}

class NotificationsDestination extends NuvoDestination {
  const NotificationsDestination();

  @override
  String get location => '/notifications';

  @override
  bool operator ==(Object other) => other is NotificationsDestination;
  @override
  int get hashCode => 0x0d17;
}
