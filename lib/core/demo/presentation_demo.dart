import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/arena/data/arena_models.dart';
import '../../features/auth/data/auth_models.dart';
import '../../features/crew/data/crew_api.dart';
import '../../features/notifications/data/notification_models.dart';
import '../../features/profile/data/progression_models.dart' show NuvoBadge;
import '../../features/races/data/race_models.dart';
import '../../features/social/data/crew_activity_models.dart';
import '../../features/social/domain/nuvo_destination.dart';

/// Presentation-only account policy.
///
/// This deliberately stays outside auth and data repositories. It changes
/// what the app renders for the presentation account, but never rewrites the
/// authenticated identity or sends fixture data to the API.
const presentationDemoEmail = 'sideswifter2010@gmail.com';
const presentationDemoRacePrefix = 'presentation-demo-race-';
const presentationDemoCreatedRacePrefix = 'presentation-demo-created-';
const presentationDemoAvatarUrl = 'https://i.pravatar.cc/160?img=12';

/// Whether [presentationDemoEmail] can flip presentation mode on/off itself
/// (a Profile settings toggle) — true for that one account, regardless of
/// the toggle's current value. Backend-flagged demo identities (e.g. the
/// store-review credential) have no toggle; they are always presentation
/// mode so review/screenshots always see polished demo data.
bool canTogglePresentationMode(AuthUser? user) =>
    user?.email.trim().toLowerCase() == presentationDemoEmail;

/// Process-wide preference with serialized writes and hydration that cannot
/// overwrite a newer explicit toggle. Storage errors always leave launch usable.
class PresentationModePreferences extends ChangeNotifier {
  PresentationModePreferences({
    required Future<bool> Function() read,
    required Future<void> Function(bool enabled) write,
  }) : _read = read, _write = write;

  final Future<bool> Function() _read;
  final Future<void> Function(bool enabled) _write;
  bool _enabled = false;
  bool get enabled => _enabled;
  int _revision = 0;
  Future<void>? _hydration;
  Future<void> _writes = Future.value();

  Future<void> load() => _hydration ??= _load();

  Future<void> _load() async {
    final revision = _revision;
    try {
      final stored = await _read();
      if (revision == _revision && stored != _enabled) {
        _enabled = stored;
        notifyListeners();
      }
    } catch (_) {
      // Missing/corrupt storage keeps the default or the user's latest choice.
    }
  }

  Future<void> setEnabled(bool enabled) {
    _revision++;
    if (_enabled != enabled) {
      _enabled = enabled;
      notifyListeners();
    }
    _writes = _writes.then((_) async {
      try {
        await _write(enabled);
      } catch (_) {
        // The current session still reflects the explicitly selected mode.
      }
    });
    return _writes;
  }
}

final _presentationMode = PresentationModePreferences(
  read: () async {
    final file = await _toggleFile();
    if (!await file.exists()) return false;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> && decoded['enabled'] == true;
  },
  write: (enabled) async {
    final file = await _toggleFile();
    await file.writeAsString(jsonEncode({'enabled': enabled}));
  },
);

/// Reactive companion to [isPresentationDemoUser]. Screens and controllers
/// watching this provider refresh when hydration or an explicit toggle changes.
final presentationModeEnabledProvider = Provider<bool>((ref) {
  void changed() => ref.invalidateSelf();
  _presentationMode.addListener(changed);
  ref.onDispose(() => _presentationMode.removeListener(changed));
  return _presentationMode.enabled;
});

bool get presentationModeToggleEnabled => _presentationMode.enabled;
Future<void> ensurePresentationModeLoaded() => _presentationMode.load();
Future<void> setPresentationModeEnabled(bool enabled) =>
    _presentationMode.setEnabled(enabled);

Future<File> _toggleFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/nuvo_presentation_mode.json');
}

bool isPresentationDemoUser(AuthUser? user) {
  // Backend-flagged demo identities (the store-review credential — the
  // canonical `testing@getnuvo.net` reviewer account — and any account with
  // is_demo set) always render fixtures.
  if (user?.isDemo == true) return true;
  final email = user?.email.trim().toLowerCase();
  // The account owner's own identity is presentation mode only while they've
  // turned it on (Profile settings) — otherwise they see their real data.
  if (email == presentationDemoEmail) return presentationModeToggleEnabled;
  return false;
}

AuthUser presentedUser(AuthUser user) {
  if (!isPresentationDemoUser(user)) return user;
  return user.copyWith(fullName: 'Maya Chen', username: 'maya');
}

bool isPresentationDemoRace(String id) =>
    id.startsWith(presentationDemoRacePrefix);

bool isPresentationDemoCreatedRace(String id) =>
    id.startsWith(presentationDemoCreatedRacePrefix);

PassInfo presentationDemoPassInfo() => const PassInfo(
  memberId: 'NV-2042',
  passSlug: 'maya-chen',
  shareUrl: 'https://getnuvo.net/pass/maya-chen',
);

/// Resolve a demo-crew id (presentation-demo-crew-*) to a public profile card
/// for the presentation session — lets taps on demo crew rows open a real
/// profile instead of a dead offline error. Progression bundles are
/// deliberately varied across levels so the public identity reads
/// differently for a newcomer (Lv. 1) and a veteran (Lv. 52).
PublicProfileCard? presentationDemoProfile(String userId,
    {String? viewerId}) {
  final members = PresentationDemoData.crewMembers();
  final requests = PresentationDemoData.crewRequestPage();
  final status = members.any((m) => m.id == userId)
      ? CrewConnectionStatus.connected
      : requests.incoming.any((m) => m.id == userId)
          ? CrewConnectionStatus.pendingIncoming
          : requests.outgoing.any((m) => m.id == userId)
              ? CrewConnectionStatus.pendingOutgoing
              : null;
  if (status == null) return null;
  final me = viewerId ?? 'presentation-demo-viewer';
  for (final person in PresentationDemoData.knownPeople()) {
    if (person.id == userId) {
      final p = _demoProgression[userId];
      return PublicProfileCard(
        id: person.id,
        displayName: person.displayName,
        initials: person.initials,
        connectionStatus: status,
        username: person.username,
        memberId: person.memberId,
        profilePhotoUrl: person.profilePhotoUrl,
        lastActiveAt: person.lastActiveAt,
        level: p?.level,
        levelProgress: p?.levelProgress,
        achievementsEarned: p?.earned.length,
        achievementsTotal: p == null ? null : _demoAchievementTotal,
        featured: p?.featured ?? const [],
        earned: p?.earned ?? const [],
        racesFinished: p?.races,
        racesWon: p?.wins,
        racesWithYou: p?.shared?.toCard(me),
      );
    }
  }
  return null;
}

/// One earned badge in a demo person's collection.
NuvoBadge _demoBadge(
  String key,
  String name,
  String iconKey,
  String category, {
  bool featured = false,
  bool milestone = false,
}) =>
    NuvoBadge(
      unlockId: 'demo-ach-$key',
      type: 'achievement',
      key: key,
      name: name,
      description: null,
      requiredLevel: 0,
      metadata: milestone ? const {'rarity': 'milestone'} : null,
      unlocked: true,
      unlockedAt: '2026-09-10T12:00:00.000Z',
      featured: featured,
      category: category,
      iconKey: iconKey,
    );

const _demoAchievementTotal = 43;

/// Sentinel for "the demo viewer won this shared race" — resolved to the
/// actual signed-in demo user id when the card is built.
const _demoViewerId = 'presentation-demo-viewer';

class _DemoShared {
  const _DemoShared(this.total, this.viewerWins, this.targetWins, this.recent);
  final int total;
  final int viewerWins;
  final int targetWins;
  final List<PublicSharedRace> recent;
  PublicRacesWithYou toCard(String viewerId) => PublicRacesWithYou(
        total: total,
        viewerWins: viewerWins,
        targetWins: targetWins,
        recent: [
          for (final r in recent)
            PublicSharedRace(
              raceId: r.raceId,
              title: r.title,
              winnerUserId:
                  r.winnerUserId == _demoViewerId ? viewerId : r.winnerUserId,
            ),
        ],
      );
}

class _DemoProgression {
  const _DemoProgression({
    required this.level,
    required this.levelProgress,
    required this.races,
    required this.wins,
    required this.earned,
    this.shared,
  });
  final int level;
  final double levelProgress;
  final int races;
  final int wins;
  final List<NuvoBadge> earned;
  final _DemoShared? shared;
  List<PublicFeaturedBadge> get featured => earned
      .where((b) => b.featured)
      .map((b) => PublicFeaturedBadge(
            unlockId: b.unlockId,
            key: b.key,
            name: b.name,
            iconKey: b.iconKey,
          ))
      .toList();
}

/// Per-person demo progression — every bundle is internally consistent with
/// what the level implies (a Lv. 52 veteran holds Champion; a Lv. 1
/// newcomer holds nothing yet).
final _demoProgression = <String, _DemoProgression>{
  'presentation-demo-crew-noah': _DemoProgression(
    level: 27,
    levelProgress: 0.6,
    races: 31,
    wins: 16,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
      _demoBadge('five_deep', 'Five Deep', 'flags_5', 'racing'),
      _demoBadge('double_digits', 'Double Digits', 'num_10', 'racing'),
      _demoBadge('quarter_century', 'Quarter Century', 'num_25', 'racing',
          milestone: true),
      _demoBadge('first_w', 'First W', 'trophy_1', 'winning'),
      _demoBadge('hat_trick', 'Hat Trick', 'trophy_3', 'winning'),
      _demoBadge('high_five', 'High Five', 'trophy_5', 'winning'),
      _demoBadge('ten_up', 'Ten Up', 'trophy_10', 'winning',
          featured: true, milestone: true),
      _demoBadge('race_maker', 'Race Maker', 'flag_plus', 'creation'),
      _demoBadge('personal_best', 'Personal Best', 'spark_up', 'performance',
          featured: true),
      _demoBadge('getting_better', 'Getting Better', 'chart_up',
          'performance'),
      _demoBadge('motion_rookie', 'Motion Rookie', 'motion_figure', 'motion'),
      _demoBadge('crewmate', 'Crewmate', 'people', 'social'),
      _demoBadge('variety_pack', 'Variety Pack', 'crossed_flags', 'variety',
          featured: true),
      _demoBadge('level_5', 'Level 5', 'num_5', 'level'),
      _demoBadge('level_10', 'Level 10', 'num_10', 'level'),
      _demoBadge('level_25', 'Level 25', 'num_25', 'level', milestone: true),
    ],
    shared: _DemoShared(12, 7, 5, [
      PublicSharedRace(
        raceId: '${presentationDemoRacePrefix}running',
        title: 'First To 50 Running In Place',
        winnerUserId: _demoViewerId,
      ),
    ]),
  ),
  'presentation-demo-crew-priya': _DemoProgression(
    level: 8,
    levelProgress: 0.35,
    races: 11,
    wins: 4,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
      _demoBadge('five_deep', 'Five Deep', 'flags_5', 'racing'),
      _demoBadge('double_digits', 'Double Digits', 'num_10', 'racing',
          featured: true),
      _demoBadge('first_w', 'First W', 'trophy_1', 'winning',
          featured: true),
      _demoBadge('hat_trick', 'Hat Trick', 'trophy_3', 'winning',
          featured: true),
      _demoBadge('race_maker', 'Race Maker', 'flag_plus', 'creation'),
      _demoBadge('personal_best', 'Personal Best', 'spark_up', 'performance'),
      _demoBadge('level_5', 'Level 5', 'num_5', 'level'),
    ],
    shared: _DemoShared(6, 4, 2, [
      PublicSharedRace(
        raceId: '${presentationDemoRacePrefix}lunges',
        title: 'First To 30 Lunges',
        winnerUserId: _demoViewerId,
      ),
    ]),
  ),
  'presentation-demo-crew-theo': _DemoProgression(
    level: 52,
    levelProgress: 0.8,
    races: 87,
    wins: 51,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
      _demoBadge('five_deep', 'Five Deep', 'flags_5', 'racing'),
      _demoBadge('double_digits', 'Double Digits', 'num_10', 'racing'),
      _demoBadge('quarter_century', 'Quarter Century', 'num_25', 'racing'),
      _demoBadge('fifty_strong', 'Fifty Strong', 'num_50', 'racing',
          featured: true, milestone: true),
      _demoBadge('first_w', 'First W', 'trophy_1', 'winning'),
      _demoBadge('hat_trick', 'Hat Trick', 'trophy_3', 'winning'),
      _demoBadge('high_five', 'High Five', 'trophy_5', 'winning'),
      _demoBadge('ten_up', 'Ten Up', 'trophy_10', 'winning'),
      _demoBadge('twenty_five_wins', '25 Wins', 'trophy_25', 'winning'),
      _demoBadge('champion', 'Champion', 'crown', 'winning',
          featured: true, milestone: true),
      _demoBadge('race_maker', 'Race Maker', 'flag_plus', 'creation'),
      _demoBadge('starter_pack', 'Starter Pack', 'flags_stack', 'creation'),
      _demoBadge('personal_best', 'Personal Best', 'spark_up', 'performance'),
      _demoBadge('getting_better', 'Getting Better', 'chart_up',
          'performance'),
      _demoBadge('comeback', 'Comeback', 'arrow_curve', 'performance'),
      _demoBadge('wire_to_wire', 'Wire to Wire', 'crown', 'performance'),
      _demoBadge('motion_rookie', 'Motion Rookie', 'motion_figure', 'motion'),
      _demoBadge('motion_regular', 'Motion Regular', 'motion_figure',
          'motion'),
      _demoBadge('motion_machine', 'Motion Machine', 'motion_figure',
          'motion', featured: true),
      _demoBadge('crewmate', 'Crewmate', 'people', 'social'),
      _demoBadge('crowd_favorite', 'Crowd Favorite', 'people', 'social'),
      _demoBadge('rivalry', 'Rivalry', 'crossed_flags', 'social'),
      _demoBadge('variety_pack', 'Variety Pack', 'crossed_flags', 'variety'),
      _demoBadge('all_rounder', 'All-Rounder', 'crossed_flags', 'variety'),
      _demoBadge('level_5', 'Level 5', 'num_5', 'level'),
      _demoBadge('level_10', 'Level 10', 'num_10', 'level'),
      _demoBadge('level_25', 'Level 25', 'num_25', 'level'),
      _demoBadge('level_50', 'Level 50', 'num_50', 'level', milestone: true),
    ],
  ),
  'presentation-demo-crew-lena': const _DemoProgression(
    level: 1,
    levelProgress: 0,
    races: 0,
    wins: 0,
    earned: [],
  ),
  'presentation-demo-crew-jules': _DemoProgression(
    level: 14,
    levelProgress: 0.5,
    races: 19,
    wins: 6,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
      _demoBadge('five_deep', 'Five Deep', 'flags_5', 'racing'),
      _demoBadge('double_digits', 'Double Digits', 'num_10', 'racing',
          featured: true),
      _demoBadge('first_w', 'First W', 'trophy_1', 'winning'),
      _demoBadge('hat_trick', 'Hat Trick', 'trophy_3', 'winning'),
      _demoBadge('high_five', 'High Five', 'trophy_5', 'winning',
          featured: true),
      _demoBadge('race_maker', 'Race Maker', 'flag_plus', 'creation'),
      _demoBadge('personal_best', 'Personal Best', 'spark_up', 'performance'),
      _demoBadge('motion_rookie', 'Motion Rookie', 'motion_figure', 'motion'),
      _demoBadge('crewmate', 'Crewmate', 'people', 'social'),
      _demoBadge('rivalry', 'Rivalry', 'crossed_flags', 'social',
          featured: true),
      _demoBadge('level_5', 'Level 5', 'num_5', 'level'),
      _demoBadge('level_10', 'Level 10', 'num_10', 'level'),
    ],
    shared: _DemoShared(9, 4, 5, [
      PublicSharedRace(
        raceId: '${presentationDemoRacePrefix}burpees',
        title: 'First To 20 Burpees',
        winnerUserId: 'presentation-demo-crew-jules',
      ),
    ]),
  ),
  'presentation-demo-crew-sam': _DemoProgression(
    level: 5,
    levelProgress: 0.4,
    races: 6,
    wins: 2,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
      _demoBadge('five_deep', 'Five Deep', 'flags_5', 'racing'),
      _demoBadge('first_w', 'First W', 'trophy_1', 'winning',
          featured: true),
      _demoBadge('race_maker', 'Race Maker', 'flag_plus', 'creation'),
      _demoBadge('level_5', 'Level 5', 'num_5', 'level'),
    ],
  ),
  'presentation-demo-crew-ellie': _DemoProgression(
    level: 3,
    levelProgress: 0.2,
    races: 2,
    wins: 0,
    earned: [
      _demoBadge('first_move', 'First Move', 'arrow_forward', 'racing'),
      _demoBadge('on_the_board', 'On the Board', 'flag', 'racing'),
    ],
  ),
};

/// All local presentation fixtures live here so Arena, Compete, Crew, and
/// Profile never drift into separate demo stories.
abstract final class PresentationDemoData {
  static const _createdAt = '2026-09-16T14:00:00.000Z';
  static const _roster = <_DemoRacer>[
    _DemoRacer(
      id: 'presentation-demo-crew-noah',
      name: 'Noah Williams',
      initials: 'NW',
      photoUrl: 'https://i.pravatar.cc/160?img=11',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-priya',
      name: 'Priya Shah',
      initials: 'PS',
      photoUrl: 'https://i.pravatar.cc/160?img=32',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-theo',
      name: 'Theo Martin',
      initials: 'TM',
      photoUrl: 'https://i.pravatar.cc/160?img=53',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-lena',
      name: 'Lena Ortiz',
      initials: 'LO',
      photoUrl: 'https://i.pravatar.cc/160?img=44',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-jules',
      name: 'Jules Carter',
      initials: 'JC',
      photoUrl: 'https://i.pravatar.cc/160?img=15',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-sam',
      name: 'Sam Rivera',
      initials: 'SR',
      photoUrl: 'https://i.pravatar.cc/160?img=68',
    ),
    _DemoRacer(
      id: 'presentation-demo-crew-ellie',
      name: 'Ellie Brooks',
      initials: 'EB',
      photoUrl: 'https://i.pravatar.cc/160?img=49',
    ),
  ];

  /// Demo presence is staggered so the crew page's real presence signals
  /// actually render — active, recent, and away members all appear.
  static List<PublicUser> crewMembers() {
    final now = DateTime.now().toUtc();
    return [
      PublicUser(
        id: 'presentation-demo-crew-noah',
        displayName: 'Noah Williams',
        username: 'noahw',
        memberId: 'NV-2048',
        level: 27,
        initials: 'NW',
        addedAt: _createdAt,
        profilePhotoUrl: 'https://i.pravatar.cc/160?img=11',
        lastActiveAt: now.subtract(const Duration(minutes: 45)),
      ),
      PublicUser(
        id: 'presentation-demo-crew-priya',
        displayName: 'Priya Shah',
        username: 'priyashah',
        memberId: 'NV-2051',
        level: 8,
        initials: 'PS',
        addedAt: _createdAt,
        profilePhotoUrl: 'https://i.pravatar.cc/160?img=32',
        lastActiveAt: now.subtract(const Duration(minutes: 3)),
      ),
      PublicUser(
        id: 'presentation-demo-crew-theo',
        displayName: 'Theo Martin',
        username: 'theom',
        memberId: 'NV-2056',
        level: 52,
        initials: 'TM',
        addedAt: _createdAt,
        profilePhotoUrl: 'https://i.pravatar.cc/160?img=53',
        lastActiveAt: now.subtract(const Duration(hours: 6)),
      ),
      PublicUser(
        id: 'presentation-demo-crew-lena',
        displayName: 'Lena Ortiz',
        username: 'lenao',
        memberId: 'NV-2061',
        level: 1,
        initials: 'LO',
        addedAt: _createdAt,
        profilePhotoUrl: 'https://i.pravatar.cc/160?img=44',
        lastActiveAt: now.subtract(const Duration(days: 2)),
      ),
      PublicUser(
        id: 'presentation-demo-crew-jules',
        displayName: 'Jules Carter',
        username: 'julesc',
        memberId: 'NV-2064',
        level: 14,
        initials: 'JC',
        addedAt: now.subtract(const Duration(days: 2)).toIso8601String(),
        profilePhotoUrl: 'https://i.pravatar.cc/160?img=15',
        lastActiveAt: now.subtract(const Duration(hours: 20)),
      ),
    ];
  }

  /// Demo request page — one incoming and one outgoing so both request
  /// sections render in the demo, and every action resolves locally.
  static CrewRequestPage crewRequestPage() {
    final now = DateTime.now().toUtc();
    return CrewRequestPage(
      incoming: [
        PublicUser(
          id: 'presentation-demo-crew-sam',
          displayName: 'Sam Rivera',
          username: 'samr',
          memberId: 'NV-2070',
        level: 5,
          initials: 'SR',
          addedAt: _createdAt,
          profilePhotoUrl: 'https://i.pravatar.cc/160?img=68',
          lastActiveAt: now.subtract(const Duration(minutes: 12)),
        ),
      ],
      outgoing: const [
        PublicUser(
          id: 'presentation-demo-crew-ellie',
          displayName: 'Ellie Brooks',
          username: 'ellieb',
          memberId: 'NV-2073',
        level: 3,
          initials: 'EB',
          addedAt: _createdAt,
          profilePhotoUrl: 'https://i.pravatar.cc/160?img=49',
        ),
      ],
    );
  }

  /// Every demo person the crew page can reference — members plus pending
  /// requests — so profiles resolve locally for any tappable row.
  static List<PublicUser> knownPeople() => [
    ...crewMembers(),
    ...crewRequestPage().incoming,
    ...crewRequestPage().outgoing,
  ];

  /// Fixture inbox for the presentation session — the demo crew feed should
  /// feel alive, and presentation mode is the sanctioned home for it.
  static List<NuvoNotification> notifications() => [
    NuvoNotification(
      id: 'presentation-demo-notif-request',
      category: 'crew_request',
      title: 'Sam Rivera wants to connect',
      actorName: 'Sam Rivera',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=68',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 8)),
      read: false,
      destination: const ProfileDestination('presentation-demo-crew-sam'),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-accepted',
      category: 'crew_request_accepted',
      title: 'Priya Shah accepted your crew request',
      actorName: 'Priya Shah',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=32',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 15)),
      read: false,
      destination: const ProfileDestination('presentation-demo-crew-priya'),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-joined',
      category: 'crew_connected',
      title: 'Theo Martin joined your crew',
      actorName: 'Theo Martin',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=53',
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      read: true,
      destination: const ProfileDestination('presentation-demo-crew-theo'),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-race',
      category: 'race_joined',
      title: 'Noah Williams joined your race',
      actorName: 'Noah Williams',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=11',
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
      read: true,
      destination: const RaceDestination(
        '${presentationDemoRacePrefix}pushups',
      ),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-reaction',
      category: 'reaction',
      title: 'Noah Williams reacted 🔥 to Pushup Battle',
      actorName: 'Noah Williams',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=11',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
      read: false,
      destination: const RaceDestination(
        '${presentationDemoRacePrefix}pushups',
      ),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-passed',
      category: 'passed_on_leaderboard',
      title: 'Priya Shah passed you in First To 25 Squats',
      actorName: 'Priya Shah',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=32',
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 7)),
      read: true,
      destination: const RaceDestination(
        '${presentationDemoRacePrefix}squats',
      ),
    ),
    NuvoNotification(
      id: 'presentation-demo-notif-jules',
      category: 'crew_connected',
      title: 'Jules Carter joined your crew',
      actorName: 'Jules Carter',
      actorPhotoUrl: 'https://i.pravatar.cc/160?img=15',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      read: true,
      destination: const ProfileDestination('presentation-demo-crew-jules'),
    ),
  ];

  /// Typed crew-activity fixtures — the shape GET /crew/feed serves:
  /// canonical race_events items (headlines composed client-side) plus
  /// crew-lifecycle items carrying server copy. Includes a `race_live` item
  /// so the LIVE card contract renders offline, and payload shapes that
  /// exercise the For-you tab (overtakes naming [userId]) and post CTAs.
  static List<CrewActivityItem> crewActivity(String userId) => [
        CrewActivityItem(
          id: 'evt:demo-live',
          type: 'race_live',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
          raceId: '${presentationDemoRacePrefix}pushups',
          raceTitle: 'Pushup Battle',
          entityType: 'race_event',
          entityId: 'demo-live',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}pushups'),
          reactions: const {'fire': 3},
          payload: const {
            'title': 'Pushup Battle',
            'endsAt': null,
            'participants': [
              {'name': 'Noah', 'score': 41, 'rank': 1, 'isCrew': true},
              {'name': 'You', 'score': 39, 'rank': 2, 'isMe': true},
            ],
          },
        ),
        // A second LIVE card — timed, so the countdown presentation
        // renders too. Mirrors the squats fixture board (Priya 16 · You 12).
        CrewActivityItem(
          id: 'evt:demo-live-timed',
          type: 'race_live',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
          raceId: '${presentationDemoRacePrefix}squats',
          raceTitle: 'First To 25 Squats',
          entityType: 'race_event',
          entityId: 'demo-live-timed',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}squats'),
          reactions: const {'fire': 1},
          payload: {
            'title': 'First To 25 Squats',
            'endsAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 35))
                .toIso8601String(),
            'participants': [
              {'name': 'Priya', 'score': 16, 'rank': 1, 'isCrew': true},
              {'name': 'You', 'score': 12, 'rank': 2, 'isMe': true},
            ],
          },
        ),
        CrewActivityItem(
          id: 'evt:demo-lead',
          type: 'rank_changed',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 8)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-noah',
            displayName: 'Noah Williams',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=11',
          ),
          raceId: '${presentationDemoRacePrefix}pushups',
          raceTitle: 'Pushup Battle',
          entityType: 'race_event',
          entityId: 'demo-lead',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}pushups'),
          payload: {
            'previousRank': 2,
            'newRank': 1,
            'overtakenUserIds': [userId],
          },
          reactions: const {'fire': 2, 'muscle': 1},
        ),
        CrewActivityItem(
          id: 'evt:demo-spot',
          type: 'lead_changed',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-priya',
            displayName: 'Priya Shah',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=32',
          ),
          raceId: '${presentationDemoRacePrefix}squats',
          raceTitle: 'First To 25 Squats',
          entityType: 'race_event',
          entityId: 'demo-spot',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}squats'),
          payload: {
            'newLeaderUserId': 'presentation-demo-crew-priya',
            'displacedUserId': userId,
          },
          reactions: const {'fire': 1},
        ),
        CrewActivityItem(
          id: 'evt:demo-reaction',
          type: 'reaction',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-noah',
            displayName: 'Noah Williams',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=11',
          ),
          raceId: '${presentationDemoRacePrefix}pushups',
          raceTitle: 'Pushup Battle',
          title: 'Noah Williams reacted 🔥 to Pushup Battle',
          entityType: 'race_event',
          entityId: 'demo-reaction',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}pushups'),
        ),
        CrewActivityItem(
          id: 'evt:demo-created',
          type: 'race_created',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-noah',
            displayName: 'Noah Williams',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=11',
          ),
          raceId: '${presentationDemoRacePrefix}mountain-climbers',
          raceTitle: 'First To 100 Mountain Climbers',
          entityType: 'race_event',
          entityId: 'demo-created',
          destination: const RaceDestination(
            '${presentationDemoRacePrefix}mountain-climbers',
          ),
        ),
        CrewActivityItem(
          id: 'evt:demo-joined',
          type: 'race_joined',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 45)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-jules',
            displayName: 'Jules Carter',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=15',
          ),
          raceId: '${presentationDemoRacePrefix}mountain-climbers',
          raceTitle: 'First To 100 Mountain Climbers',
          entityType: 'race_event',
          entityId: 'demo-joined',
          destination: const RaceDestination(
            '${presentationDemoRacePrefix}mountain-climbers',
          ),
        ),
        CrewActivityItem(
          id: 'evt:demo-finish',
          type: 'participant_finished',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(hours: 3)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-priya',
            displayName: 'Priya Shah',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=32',
          ),
          raceId: '${presentationDemoRacePrefix}squats',
          raceTitle: 'First To 25 Squats',
          entityType: 'race_event',
          entityId: 'demo-finish',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}squats'),
          payload: const {'score': 25},
        ),
        // "You won a race" — lands on the viewer, so it earns For you.
        // Mirrors the lunges fixture board (You 30 · Priya 24).
        CrewActivityItem(
          id: 'evt:demo-win',
          type: 'winner_determined',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(hours: 4)),
          actor: CrewActivityActor(
            id: userId,
            displayName: 'You',
            profilePhotoUrl: presentationDemoAvatarUrl,
          ),
          raceId: '${presentationDemoRacePrefix}lunges',
          raceTitle: 'First To 30 Lunges',
          entityType: 'race_event',
          entityId: 'demo-win',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}lunges'),
          payload: {'winnerUserId': userId},
          reactions: const {'clap': 2, 'fire': 1},
        ),
        CrewActivityItem(
          id: 'ntf:demo-accepted',
          type: 'crew_request_accepted',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(hours: 6)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-priya',
            displayName: 'Priya Shah',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=32',
          ),
          title: 'Priya Shah accepted your crew request',
          entityType: 'crew',
          entityId: 'demo-conn-priya',
          destination:
              const ProfileDestination('presentation-demo-crew-priya'),
          reactions: const {'clap': 1},
        ),
        CrewActivityItem(
          id: 'evt:demo-best',
          type: 'personal_best',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(hours: 5)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-lena',
            displayName: 'Lena Ortiz',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=44',
          ),
          raceId: '${presentationDemoRacePrefix}pushups',
          raceTitle: 'Pushup Battle',
          entityType: 'race_event',
          entityId: 'demo-best',
          destination:
              const RaceDestination('${presentationDemoRacePrefix}pushups'),
          payload: const {
            'previousBest': 36,
            'newBest': 42,
            'metric': 'pushups',
          },
        ),
        CrewActivityItem(
          id: 'ntf:demo-jules',
          type: 'crew_connected',
          occurredAt:
              DateTime.now().toUtc().subtract(const Duration(days: 2)),
          actor: const CrewActivityActor(
            id: 'presentation-demo-crew-jules',
            displayName: 'Jules Carter',
            profilePhotoUrl: 'https://i.pravatar.cc/160?img=15',
          ),
          title: 'Jules Carter joined your crew',
          entityType: 'crew',
          entityId: 'demo-conn-jules',
          destination:
              const ProfileDestination('presentation-demo-crew-jules'),
        ),
      ];

  static List<Race> races(String userId) => [
    _race(
      id: '${presentationDemoRacePrefix}pushups',
      creatorId: userId,
      title: 'Pushup Battle',
      activityId: 'pushups',
      targetValue: 50,
      // Mirrors the race_live payload (Noah 41 · You 39) — the fixture
      // graph stays internally consistent wherever the race surfaces.
      meValue: 39,
      opponentName: 'Noah Williams',
      opponentId: 'presentation-demo-crew-noah',
      opponentValue: 41,
      status: 'active',
    ),
    _race(
      id: '${presentationDemoRacePrefix}squats',
      creatorId: userId,
      title: 'First To 25 Squats',
      activityId: 'squats',
      targetValue: 25,
      meValue: 12,
      opponentName: 'Priya Shah',
      opponentId: 'presentation-demo-crew-priya',
      opponentValue: 16,
      status: 'active',
    ),
    _race(
      id: '${presentationDemoRacePrefix}jacks',
      creatorId: userId,
      title: 'First To 10 Jumping Jacks',
      activityId: 'jumping_jacks',
      targetValue: 10,
      meValue: 7,
      opponentName: 'Theo Martin',
      opponentId: 'presentation-demo-crew-theo',
      opponentValue: 5,
      status: 'active',
    ),
    _race(
      id: '${presentationDemoRacePrefix}mountain-climbers',
      creatorId: userId,
      title: 'First To 100 Mountain Climbers',
      activityId: 'mountain_climbers',
      targetValue: 100,
      meValue: 0,
      status: 'active',
    ),
    // Scheduled — Crew's Races tab shows it under Up next.
    _race(
      id: '${presentationDemoRacePrefix}squat-battle',
      creatorId: userId,
      title: '60 Second Squat Battle',
      activityId: 'squats',
      targetValue: 60,
      meValue: 0,
      opponentName: 'Theo Martin',
      opponentId: 'presentation-demo-crew-theo',
      status: 'scheduled',
      startLineAt:
          DateTime.now().toUtc().add(const Duration(minutes: 18)).toIso8601String(),
      finishLineAt:
          DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(),
    ),
    _race(
      id: '${presentationDemoRacePrefix}running',
      creatorId: userId,
      title: 'First To 50 Running In Place',
      activityId: 'running_in_place',
      targetValue: 50,
      meValue: 50,
      opponentName: 'Noah Williams',
      opponentId: 'presentation-demo-crew-noah',
      opponentValue: 42,
      status: 'completed',
      completedAt: '2026-09-16T15:10:00.000Z',
    ),
    _race(
      id: '${presentationDemoRacePrefix}lunges',
      creatorId: userId,
      title: 'First To 30 Lunges',
      activityId: 'lunges',
      targetValue: 30,
      meValue: 30,
      opponentName: 'Priya Shah',
      opponentId: 'presentation-demo-crew-priya',
      opponentValue: 24,
      status: 'completed',
      completedAt: '2026-09-15T18:30:00.000Z',
    ),
    _race(
      id: '${presentationDemoRacePrefix}burpees',
      creatorId: userId,
      title: 'First To 20 Burpees',
      activityId: 'burpees',
      targetValue: 20,
      // A loss — 19 to Jules' 20 — so Recent results shows a neutral
      // placement next to the wins, and Best finish stays earned.
      meValue: 19,
      opponentName: 'Jules Carter',
      opponentId: 'presentation-demo-crew-jules',
      opponentValue: 20,
      // A 1v1 battle — the padded roster would out-score me anyway and
      // bury the placement; keeping it head-to-head reads cleaner.
      rosterSize: 1,
      status: 'completed',
      completedAt: '2026-09-14T17:05:00.000Z',
    ),
  ];

  static Race createdRace({
    required String id,
    required String userId,
    required String title,
    required int targetValue,
    String? activityId,
    String? unit,
    String? customActivityName,
  }) => _race(
    id: id,
    creatorId: userId,
    title: title,
    activityId: activityId,
    targetValue: targetValue,
    meValue: 0,
    status: 'active',
    unit: unit,
    customActivityName: customActivityName,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );

  static ArenaSnapshot arenaSnapshot(String userId) {
    final demoRaces = races(userId);
    final active = demoRaces.where((race) => race.status == 'active').toList();
    final focus = active.first;
    return ArenaSnapshot(
      mode: 'real',
      headerPulse: 'Your crew is moving',
      focusBoard: _boardFor(focus, userId),
      liveBoards: [for (final race in active.skip(1)) _boardFor(race, userId)],
      activity: const [
        ArenaActivity(
          id: 'presentation-demo-activity-1',
          actorName: 'Priya Shah',
          text: 'joined your squat race',
          raceTitle: 'First To 25 Squats',
          timeLabel: '12m ago',
          type: 'joined',
        ),
        ArenaActivity(
          id: 'presentation-demo-activity-2',
          actorName: 'Noah Williams',
          text: 'submitted 8 pushups',
          raceTitle: 'First To 50 Pushups',
          timeLabel: '28m ago',
          type: 'proof_submitted',
        ),
      ],
    );
  }

  static ArenaBoard _boardFor(Race race, String userId) {
    final me = race.participantFor(userId);
    final target = race.targetValue ?? 0;
    final progress = me?.progressValue ?? 0;
    final percent = target == 0 ? 0 : ((progress / target) * 100).round();
    final rows = [
      if (me != null)
        ArenaMiniLeaderboardRow(
          label: 'Maya Chen',
          value: '$progress / $target',
          isCurrentUser: true,
          profilePhotoUrl: presentationDemoAvatarUrl,
        ),
      for (final participant in race.participants.where(
        (p) => p.userId != userId,
      ))
        ArenaMiniLeaderboardRow(
          label: participant.displayName,
          value: '${participant.progressValue} / $target',
          profilePhotoUrl: participant.profilePhotoUrl,
        ),
    ];
    return ArenaBoard(
      id: race.id,
      source: 'real',
      title: race.title,
      proofLabel: 'AI Motion Proof',
      progressLabel: '$progress / $target reps',
      boardContext: 'Your crew is moving toward the finish line.',
      primaryActionLabel: 'Open race',
      primaryActionType: 'open_board',
      progressPercent: percent.clamp(0, 100),
      racerCount: race.participantCount,
      isResult: false,
      miniLeaderboard: rows,
      myRank: race.participantFor(userId)?.rank,
    );
  }

  static Race _race({
    required String id,
    required String creatorId,
    required String title,
    required String? activityId,
    required int targetValue,
    required int meValue,
    String? opponentName,
    String? opponentId,
    int opponentValue = 0,
    required String status,
    String? completedAt,
    String? unit,
    String? customActivityName,
    String? createdAt,
    String? startLineAt,
    String? finishLineAt,
    int rosterSize = 7,
  }) {
    final opponentRoster = <_DemoRacer>[
      if (opponentName != null && opponentId != null)
        _DemoRacer(
          id: opponentId,
          name: opponentName,
          initials: _initials(opponentName),
          photoUrl: _photoFor(opponentId),
        ),
      ..._roster.where((racer) => racer.id != opponentId),
    ].take(rosterSize).toList();
    final opponentValues = [
      for (var i = 0; i < opponentRoster.length; i++)
        opponentRoster[i].id == opponentId
            ? opponentValue.clamp(0, targetValue)
            : _rosterValue(meValue, targetValue, i),
    ];
    final myRank = 1 + opponentValues.where((value) => value > meValue).length;
    final participants = <Map<String, dynamic>>[
      {
        'id': '$id-me',
        'userId': creatorId,
        'displayName': 'Maya Chen',
        'profilePhotoUrl': presentationDemoAvatarUrl,
        'progressValue': meValue,
        'progressPercent': ((meValue / targetValue) * 100).round(),
        'rank': myRank,
        'joinedAt': _createdAt,
      },
    ];
    for (var i = 0; i < opponentRoster.length; i++) {
      final racer = opponentRoster[i];
      final value = opponentValues[i];
      participants.add({
        'id': '$id-${racer.id}',
        'userId': racer.id,
        'displayName': racer.name,
        'profilePhotoUrl': racer.photoUrl,
        'progressValue': value,
        'progressPercent': ((value / targetValue) * 100).round(),
        'rank': value > meValue ? 1 : 2,
        'joinedAt': _createdAt,
      });
    }
    final standings = status == 'completed'
        ? [
            for (final participant in participants)
              {
                'userId': participant['userId'],
                'displayName': participant['displayName'],
                'rank': participant['rank'],
                'scoreValue': participant['progressValue'],
                'completedAt': completedAt,
              },
          ]
        : const <Map<String, dynamic>>[];
    final payload = <String, dynamic>{
      'id': id,
      'creatorId': creatorId,
      'title': title,
      'goalType': 'manual',
      'targetValue': targetValue,
      'unit': unit ?? 'reps',
      'targetUnit': unit ?? 'reps',
      'activityId': activityId,
      'aiActivityType': activityId,
      'metric': unit ?? 'reps',
      'verificationMethod': 'camera_pose',
      'proofRequirement': 'ai_check',
      'proofReviewMode': 'auto_accept',
      'visibility': 'crew_only',
      'status': status,
      'completedAt': completedAt,
      'startLineAt': startLineAt,
      'finishLineAt': finishLineAt,
      'createdAt': createdAt ?? _createdAt,
      'updatedAt': createdAt ?? _createdAt,
      'participants': participants,
      'finalStandings': standings,
    };
    if (customActivityName case final name?) {
      payload['customActivityName'] = name;
    }
    if (activityId == 'basketball_shot') {
      payload['verifierReleaseId'] = 'basketball_shot-composition-2026.09.1';
      payload['verifierSpec'] = _basketballVerifierSpec();
    }
    return Race.fromJson(payload);
  }

  static Map<String, dynamic> _basketballVerifierSpec() => {
    'specSchemaVersion': 1,
    'releaseId': 'basketball_shot-composition-2026.09.1',
    'activityId': 'basketball_shot',
    'engineType': 'object_composition_v1',
    'measurementType': 'repetitions',
    'requiredCapabilities': const [
      'pose_landmarks_v1',
      'object_dots_v1',
      'object_composition_v1',
    ],
    'requiredLandmarks': const ['leftWrist', 'rightWrist'],
    'requiredObjects': const [
      {'id': 'ball', 'kind': 'ball', 'minLikelihood': 0.45},
      {'id': 'hoop', 'kind': 'hoop', 'minLikelihood': 0.55},
    ],
    'model': {
      'modelVersion': 'basketball-yolox-s-800',
      'inputSchemaVersion': 1,
      'artifactSha256':
          'dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425',
      'inputSize': 800,
    },
    'composition': {
      'states': const [
        'ready',
        'released',
        'ascending',
        'descending',
        'made',
        'missed',
      ],
      'transitions': const [
        {'from': 'ready', 'to': 'released', 'event': 'ball_released'},
        {'from': 'released', 'to': 'ascending', 'event': 'ball_ascending'},
        {'from': 'ascending', 'to': 'descending', 'event': 'ball_descending'},
        {'from': 'descending', 'to': 'made', 'event': 'ball_through_hoop'},
        {'from': 'ascending', 'to': 'missed', 'event': 'shot_timeout'},
        {'from': 'descending', 'to': 'missed', 'event': 'shot_timeout'},
      ],
      'startState': 'ready',
      'terminalStates': const ['made', 'missed'],
      'ballObjectId': 'ball',
      'hoopObjectId': 'hoop',
      'stableFrames': 2,
      'maxShotMs': 8000,
      'controlDistance': 0.22,
      'releaseDistance': 0.16,
      'minUpwardVelocity': 0.06,
      'minDownwardVelocity': 0.04,
      'hoopPlaneTolerance': 0.08,
      'madeRadius': 0.18,
    },
  };

  static String _photoFor(String id) {
    final index = _roster.indexWhere((racer) => racer.id == id);
    return index == -1 ? _roster.first.photoUrl : _roster[index].photoUrl;
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();
  }

  static int _rosterValue(int meValue, int targetValue, int index) {
    if (meValue == 0) return 0;
    return (meValue + ((index + 2) * 3) - 8).clamp(0, targetValue);
  }
}

class _DemoRacer {
  const _DemoRacer({
    required this.id,
    required this.name,
    required this.initials,
    required this.photoUrl,
  });

  final String id;
  final String name;
  final String initials;
  final String photoUrl;
}
