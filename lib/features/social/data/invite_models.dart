import '../domain/nuvo_destination.dart';
import 'package:nuvo/core/utils/json_safe.dart';

/// Availability of an invite token, mirrored from the Worker.
enum InviteStatus {
  active,
  expired,
  revoked,
  used,
  notFound,
  blocked,

  /// The race behind the invite has ended (server 410 `status: 'closed'`).
  closed,
  unknown,
}

InviteStatus _statusFrom(String? raw) {
  switch (raw) {
    case 'active':
      return InviteStatus.active;
    case 'expired':
      return InviteStatus.expired;
    case 'revoked':
      return InviteStatus.revoked;
    case 'used':
      return InviteStatus.used;
    case 'not_found':
      return InviteStatus.notFound;
    case 'blocked':
      return InviteStatus.blocked;
    case 'closed':
      return InviteStatus.closed;
    default:
      return InviteStatus.unknown;
  }
}

/// Status from a response body: the explicit `status` wins; an unrecognised
/// one falls back to the `error` text so a "race has ended" message still
/// reads as closed rather than a generic failure.
InviteStatus _statusFromBody(Map<String, dynamic> json) {
  final status = _statusFrom(jStr(json['status']));
  if (status != InviteStatus.unknown) return status;
  final error = json['error'];
  if (error is String &&
      RegExp(r'\b(closed|ended|finished)\b', caseSensitive: false)
          .hasMatch(error)) {
    return InviteStatus.closed;
  }
  return InviteStatus.unknown;
}

/// The safe, minimal preview for `/invite/:token`. Works logged-out.
class InvitePreview {
  const InvitePreview({
    required this.status,
    required this.kind,
    required this.requiresAuth,
    this.destination,
    this.race,
    this.person,
  });

  final InviteStatus status;

  /// 'race_join' | 'crew_connect' | 'squad_join' | null when unavailable.
  final String? kind;

  /// The server says a logged-out viewer must authenticate before accepting.
  final bool requiresAuth;

  /// Where accepting will land — resolved from the server's structured
  /// descriptor, never a raw route string.
  final NuvoDestination? destination;

  final RaceInviteCard? race;
  final PersonInviteCard? person;

  bool get isAvailable => status == InviteStatus.active;

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    final preview = json['preview'] as Map<String, dynamic>?;
    return InvitePreview(
      status: _statusFromBody(json),
      kind: jStr(json['kind']),
      requiresAuth: jBool(json['requiresAuth']) ?? true,
      destination: NuvoDestination.fromDescriptor(
        json['destination'] as Map<String, dynamic>?,
      ),
      race: preview?['race'] is Map<String, dynamic>
          ? RaceInviteCard.fromJson(preview!['race'] as Map<String, dynamic>)
          : null,
      person: (preview?['person'] ?? preview?['inviter']) is Map<String, dynamic>
          ? PersonInviteCard.fromJson(
              (preview!['person'] ?? preview['inviter']) as Map<String, dynamic>,
            )
          : null,
    );
  }

  factory InvitePreview.unavailable(InviteStatus status) => InvitePreview(
        status: status,
        kind: null,
        requiresAuth: false,
      );
}

class RaceInviteCard {
  const RaceInviteCard({
    required this.id,
    required this.title,
    this.activityId,
    this.targetValue,
    this.targetUnit,
    this.goalType,
    this.participantCount = 0,
    this.creatorName,
    this.creatorPhotoUrl,
    this.alreadyJoined = false,
    this.visibility,
    this.status,
  });

  final String id;
  final String title;
  final String? activityId;
  final int? targetValue;
  final String? targetUnit;
  final String? goalType;
  final int participantCount;
  final String? creatorName;
  final String? creatorPhotoUrl;
  final bool alreadyJoined;
  final String? visibility;
  final String? status;

  factory RaceInviteCard.fromJson(Map<String, dynamic> j) => RaceInviteCard(
        id: (jStr(j['id']) ?? ''),
        title: jStr(j['title']) ?? 'Race',
        activityId: jStr(j['activityId']),
        targetValue: jInt(j['targetValue']),
        targetUnit: jStr(j['targetUnit']),
        goalType: jStr(j['goalType']),
        participantCount: jInt(j['participantCount']) ?? 0,
        creatorName: (j['creator'] as Map<String, dynamic>?)?['displayName'] as String?,
        creatorPhotoUrl:
            (j['creator'] as Map<String, dynamic>?)?['profilePhotoUrl'] as String?,
        alreadyJoined: jBool(j['alreadyJoined']) ?? false,
        visibility: jStr(j['visibility']),
        status: jStr(j['status']),
      );
}

class PersonInviteCard {
  const PersonInviteCard({
    required this.userId,
    required this.displayName,
    this.username,
    this.profilePhotoUrl,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? profilePhotoUrl;

  factory PersonInviteCard.fromJson(Map<String, dynamic> j) => PersonInviteCard(
        userId: jStr(j['userId']) ?? '',
        displayName: jStr(j['displayName']) ?? 'Nuvo member',
        username: jStr(j['username']),
        profilePhotoUrl: jStr(j['profilePhotoUrl']),
      );
}

/// Result of `POST /invites/:token/accept`.
class InviteAcceptResult {
  const InviteAcceptResult({
    required this.status,
    this.kind,
    this.destination,
    this.alreadyJoined = false,
    this.connectionStatus,
  });

  final InviteStatus status;
  final String? kind;
  final NuvoDestination? destination;
  final bool alreadyJoined;

  /// 'active' | 'pending' for a crew connect.
  final String? connectionStatus;

  bool get ok => status == InviteStatus.active;

  factory InviteAcceptResult.fromJson(Map<String, dynamic> j) => InviteAcceptResult(
        status: j['ok'] == true
            ? InviteStatus.active
            : _statusFromBody(j),
        kind: jStr(j['kind']),
        destination: NuvoDestination.fromDescriptor(
          j['destination'] as Map<String, dynamic>?,
        ),
        alreadyJoined: jBool(j['alreadyJoined']) ?? false,
        connectionStatus: jStr(j['connectionStatus']),
      );
}

/// Result of `POST /invites` (minting).
class MintedInvite {
  const MintedInvite({required this.token, required this.url, this.code, this.kind});

  final String token;
  final String url;
  final String? code;
  final String? kind;

  factory MintedInvite.fromJson(Map<String, dynamic> j) => MintedInvite(
        token: (jStr(j['token']) ?? ''),
        url: (jStr(j['url']) ?? ''),
        code: jStr(j['code']),
        kind: jStr(j['kind']),
      );
}
