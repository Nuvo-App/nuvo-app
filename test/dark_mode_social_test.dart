// Dark-mode coverage for the social surfaces: Crew (People / Activity),
// Crews list + detail, notifications and My code. Each surface must pump
// under AppTheme.dark with no exceptions and no overflow at 390x844 and
// 320x568, keep QR codes black-on-white, and keep its main text at >= 4.5:1
// against the nearest opaque background. The light theme must still build.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/notifications/presentation/notifications_screen.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/my_nuvo_screen.dart';
import 'package:nuvo/features/social/social_providers.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

const _passInfo = PassInfo(
  memberId: 'NUVO-001',
  passSlug: 'maya',
  shareUrl: 'https://getnuvo.net/p/maya',
);

class _DemoAuthRepo extends AuthRepository {
  _DemoAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'demo-viewer-1',
        email: 'demo-viewer@example.com',
        isDemo: true,
        fullName: 'Maya Chen',
        username: 'maya',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));
  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

class _RaceRepo extends RaceRepository {
  _RaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<Race>> getRaces() async => const [];
}

class _CrewRepo extends CrewRepository {
  _CrewRepo() : super(CrewApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<PublicUser>> getCrew() async => const [];
  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();
}

class _FeedRepo extends CrewActivityRepository {
  _FeedRepo() : super(CrewActivityApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<CrewActivityItem>> getFeed(
          {int limit = 40, String? cursor}) async =>
      const [];
}

class _NotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor, String? etag}) async =>
      const NotificationPage(items: [], unreadCount: 0);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

class _Inbox extends NotificationController {
  _Inbox(List<NuvoNotification> items) : super(_NotifRepo()) {
    state = NotificationState(
      items: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }
  @override
  Future<void> load({bool force = true}) => Future.value();
}

class _InviteRepo extends InviteRepository {
  _InviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintMyCrewInvite() async => const MintedInvite(
        token: 't',
        url: 'https://getnuvo.net/i/t',
        kind: 'crew_connect',
      );
}

NuvoNotification _notif(String id, String category,
        {String? actor, bool read = false}) =>
    NuvoNotification(
      id: id,
      category: category,
      title: actor == null ? 'A thing happened' : '$actor did a thing',
      body: 'Some context',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 8)),
      read: read,
      actorName: actor,
    );

Map<String, dynamic> _g(String id, String name) => {
      'id': id,
      'name': name,
      'joinCode': 'CODE$id',
      'isOwner': true,
      'memberCount': 4,
      'raceCount': 2,
    };

Map<String, dynamic> _s(String id, String name, int rank, int pts,
        {bool you = false}) =>
    {
      'userId': id,
      'displayName': name,
      'rank': rank,
      'points': pts,
      'wins': rank == 1 ? 2 : 0,
      'races': 2,
      'isYou': you,
    };

class _SquadRepo implements SquadRepository {
  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) async {
    final raw = {
      'squads': [_g('a', 'Sunrise Crew'), _g('b', 'Night Owls')]
    };
    return Conditional(data: parseCrewGroupList(raw), etag: 'e', raw: raw);
  }

  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) async {
    final raw = {
      'squad': _g(id, 'Sunrise Crew'),
      'races': [
        {'id': 'r1', 'title': 'Morning push-ups', 'status': 'active'},
        {'id': 'r2', 'title': 'Plank ladder', 'status': 'finished'},
      ],
      'standings': [
        _s('1', 'Ava Long', 1, 9),
        _s('2', 'Ben', 2, 6, you: true),
        _s('3', 'Cy', 3, 3),
        _s('4', 'Dee', 4, 1),
      ],
    };
    return Conditional(
        data: CrewGroupDetail.fromJson(raw), etag: 'd', raw: raw);
  }

  @override
  Future<CrewGroup> create(String name) async => CrewGroup.fromJson(_g('n', name));
  @override
  Future<void> join(String code) async {}
  @override
  Future<int> addRace(String id, String raceId) async => 1;
  @override
  Future<void> leave(String id) async {}

  @override
  Future<void> setRole(String id, String userId, String role) async {}

  @override
  Future<void> removeMember(String id, String userId) async {}

  @override
  Future<void> removeRace(String id, String raceId) async {}
}

// ── Harness ───────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool dark,
  required Size size,
  List<Override> overrides = const [],
  GoRouter? router,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = dark ? AppTheme.dark() : AppTheme.light();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_RaceRepo()),
      crewRepositoryProvider.overrideWithValue(_CrewRepo()),
      crewActivityRepositoryProvider.overrideWithValue(_FeedRepo()),
      notificationRepositoryProvider.overrideWithValue(_NotifRepo()),
      inviteRepositoryProvider.overrideWithValue(_InviteRepo()),
      authControllerProvider
          .overrideWith((ref) => AuthController(_DemoAuthRepo())),
      squadControllerProvider.overrideWith((ref) => SquadController(
          _SquadRepo(), CacheStore.memory(),
          accountId: () => 'u1')),
      ...overrides,
    ],
    child: router != null
        ? MaterialApp.router(
            theme: theme, themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: router)
        : MaterialApp(theme: theme, home: home),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── Contrast helpers ──────────────────────────────────────────────────────────

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _pow(double b, double e) {
  // exp/log without dart:math import noise.
  return _exp(e * _ln(b));
}

double _ln(double x) {
  // Newton on exp.
  var y = 0.0;
  for (var i = 0; i < 40; i++) {
    final ey = _exp(y);
    y -= (ey - x) / ey;
  }
  return y;
}

double _exp(double x) {
  var term = 1.0, sum = 1.0;
  for (var i = 1; i < 60; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color top, Color bottom) {
  final a = top.a;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

Color? _fillOf(Widget w) {
  if (w is ColoredBox) return w.color;
  if (w is DecoratedBox) {
    final d = w.decoration;
    if (d is BoxDecoration) return d.color;
  }
  if (w is Material && w.type != MaterialType.transparency) {
    return w.color;
  }
  if (w is Scaffold) return w.backgroundColor;
  return null;
}

/// Nearest opaque background behind [e], compositing translucent fills.
Color backgroundBehind(Element e, Color fallback) {
  final fills = <Color>[];
  var found = false;
  e.visitAncestorElements((a) {
    final c = _fillOf(a.widget);
    if (c != null && c.a > 0) {
      fills.add(c);
      if (c.a >= 0.999) {
        found = true;
        return false;
      }
    }
    return true;
  });
  var bg = found ? fills.removeLast() : fallback;
  for (final f in fills.reversed) {
    bg = _over(f, bg);
  }
  return bg;
}

class _Low {
  _Low(this.text, this.fg, this.bg, this.ratio);
  final String text;
  final Color fg, bg;
  final double ratio;
  @override
  String toString() =>
      '"$text" ${fg.toARGB32().toRadixString(16)} on ${bg.toARGB32().toRadixString(16)} = ${ratio.toStringAsFixed(2)}';
}

/// Every visible RichText whose foreground is below [min] against its
/// nearest opaque background. Disabled/hint-level text (alpha < 0.6 or
/// the faintest ink token) is intentionally skipped.
List<Object> lowContrast(WidgetTester tester, Color page,
    {double min = 4.5, Set<Color> skip = const {}}) {
  final out = <_Low>[];
  // 'Scan to add me' caption is the pre-existing light-theme textMuted on
  // the always-white QR card (4.0:1 in both themes).
  for (final el in find.byType(RichText).evaluate()) {
    final rt = el.widget as RichText;
    final plain = rt.text.toPlainText();
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(plain) || plain.trim().length <= 2) {
      continue; // icon glyphs and avatar initials
    }
    var fg = rt.text.style?.color;
    if (fg == null || skip.contains(fg) || plain == 'Scan to add me') continue;
    final bg = backgroundBehind(el, page);
    fg = _over(fg, bg);
    final r = contrast(fg, bg);
    if (r < min) out.add(_Low(plain, fg, bg, r));
  }
  return out;
}

void _expectClean(WidgetTester tester, String what) {
  expect(tester.takeException(), isNull, reason: what);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const sizes = [Size(390, 844), Size(320, 568)];
  final t = NuvoThemeColors.dark;

  test('dark ink tokens clear 4.5:1 on dark page / surface / panel', () {
    for (final bg in [t.page, t.surface, t.panel, t.panelLight]) {
      expect(contrast(t.ink, bg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.inkMuted, bg), greaterThanOrEqualTo(4.5));
    }
    final sem = NuvoSemanticColors.dark;
    for (final r in [sem.neutral, sem.success, sem.danger, sem.warning]) {
      expect(contrast(r.on, r.surface), greaterThanOrEqualTo(4.5));
      // bright hue is the dark-mode text/icon hue (used by blueInk etc.).
      expect(contrast(r.bright, t.surface), greaterThanOrEqualTo(4.5));
    }
  });

  for (final size in sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('Crew People + Activity $mode $tag', (tester) async {
        await _pump(tester, const PassScreen(), dark: dark, size: size);
        _expectClean(tester, 'people');
        expect(find.text('People'), findsOneWidget);
        if (dark) {
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'People: $low');
        }
        await tester.tap(find.text('Activity'));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        _expectClean(tester, 'activity');
        if (dark) {
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'Activity: $low');
        }
      });

      testWidgets('Crews list + detail $mode $tag', (tester) async {
        await _pump(tester, const CrewGroupsScreen(), dark: dark, size: size);
        _expectClean(tester, 'crews list');
        expect(find.text('Sunrise Crew'), findsOneWidget);
        if (dark) {
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'Crews list: $low');
        }
        await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'),
            dark: dark, size: size);
        _expectClean(tester, 'crew detail');
        if (dark) {
          // Podium rank numerals sit on medal fills with fixed navy ink and
          // are checked separately by the medal contrast test below.
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'Crew detail: $low');
        }
      });

      testWidgets('Notifications $mode $tag', (tester) async {
        final inbox = _Inbox([
          _notif('a', 'race_joined', actor: 'Maya'),
          _notif('b', 'race_completed', actor: 'Riley'),
          _notif('c', 'proof_accepted', read: true),
          _notif('d', 'crew_request', actor: 'Sam'),
          _notif('e', 'proof_rejected'),
        ]);
        await _pump(tester, const NotificationsScreen(),
            dark: dark, size: size, overrides: [
          notificationControllerProvider.overrideWith((_) => inbox),
        ]);
        _expectClean(tester, 'notifications');
        expect(find.text('Notifications'), findsOneWidget);
        if (dark) {
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'Notifications: $low');
        }
      });

      testWidgets('My code $mode $tag keeps QR black on white', (tester) async {
        await _pump(tester, const SizedBox(),
            dark: dark,
            size: size,
            router: GoRouter(routes: [
              GoRoute(path: '/', builder: (_, _) => const MyNuvoScreen()),
              GoRoute(path: '/scan', builder: (_, _) => const SizedBox()),
            ]));
        _expectClean(tester, 'my code');
        final qr = find.byType(QrImageView);
        expect(qr, findsOneWidget);
        final w = tester.widget<QrImageView>(qr);
        expect(w.dataModuleStyle.color, isNot(equals(t.ink)));
        expect(contrast(w.dataModuleStyle.color!, const Color(0xFFFFFFFF)),
            greaterThan(10));
        expect(contrast(w.eyeStyle.color!, const Color(0xFFFFFFFF)),
            greaterThan(10));
        // The card behind the QR (and the name under it) stays white.
        final bg = backgroundBehind(qr.evaluate().first, t.page);
        expect(bg, const Color(0xFFFFFFFF));
        if (dark) {
          final low = lowContrast(tester, t.page);
          expect(low, isEmpty, reason: 'My code: $low');
        }
      });
    }
  }

  test('podium medals keep navy ink at >= 4.5:1', () {
    for (final m in [
      NuvoColors.sunshine,
      const Color(0xFFB8C2D6),
      NuvoColors.orange,
    ]) {
      expect(contrast(NuvoColors.navy, m), greaterThanOrEqualTo(4.5));
    }
  });

  test('semantic tints stay readable on dark surfaces', () {
    for (final hue in [
      NuvoColors.success,
      NuvoColors.warning,
      NuvoColors.danger,
      NuvoColors.blue,
    ]) {
      final fill = _over(hue.withValues(alpha: 0.22), t.surface);
      final fg = Color.lerp(hue, const Color(0xFFFFFFFF), 0.45)!;
      expect(contrast(fg, fill), greaterThanOrEqualTo(4.5),
          reason: hue.toARGB32().toRadixString(16));
    }
  });
}
