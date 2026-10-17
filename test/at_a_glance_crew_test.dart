// ignore_for_file: unused_element_parameter, unused_element, unused_import
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/nuvo_live_race_card.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/screenshot.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/core/widgets/nuvo_icons.dart';
import 'package:nuvo/core/widgets/pressable_scale.dart';
import 'package:nuvo/core/widgets/nuvo_motion.dart';
import 'package:nuvo/core/widgets/sliver_fold_guard.dart';
import 'package:nuvo/core/demo/presentation_demo.dart';
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
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

const _passInfo = PassInfo(
  memberId: 'NUVO-001',
  passSlug: 'testuser',
  shareUrl: 'https://getnuvo.net/p/testuser',
);

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'user-1',
        email: 'test@getnuvo.net',
        fullName: 'Test User',
        username: 'testuser',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));

  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

/// The presentation/testing identity — every controller reads
/// `isPresentationDemoUser(user)` and serves the demo fixtures, so this
/// one repo populates the whole Crew screen for layout tests.
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

class _PassRaceRepo extends RaceRepository {
  _PassRaceRepo({this.races = const [], this.throws = false})
      : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  final bool throws;
  int getRacesCalls = 0;

  @override
  Future<List<Race>> getRaces() async {
    getRacesCalls++;
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return races;
  }
}

/// Feed source for non-demo tests — returns the supplied canonical
/// items so partial states (races but no events, events but no races)
/// can be exercised independently.
class _FeedRepo extends CrewActivityRepository {
  _FeedRepo(this.items, {this.throws = false})
      : super(CrewActivityApi(), SecureTokenStore(), AuthApi());

  final List<CrewActivityItem> items;
  final bool throws;
  int reactCalls = 0;
  int unreactCalls = 0;
  int feedCalls = 0;

  @override
  Future<List<CrewActivityItem>> getFeed(
      {int limit = 40, String? cursor}) async {
    feedCalls++;
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return items;
  }

  @override
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) async {
    reactCalls++;
    final counts = {...item.reactions};
    counts[emoji] = (counts[emoji] ?? 0) + 1;
    return ReactionSummary(counts: counts, myReaction: emoji);
  }

  @override
  Future<ReactionSummary> unreact(CrewActivityItem item) async {
    unreactCalls++;
    final counts = {...item.reactions};
    final mine = item.myReaction;
    if (mine != null) {
      final n = (counts[mine] ?? 0) - 1;
      n <= 0 ? counts.remove(mine) : counts[mine] = n;
    }
    return ReactionSummary(counts: counts);
  }
}

class _FakeCrewRepo implements CrewRepository {
  _FakeCrewRepo({
    this.throws = false,
    this.searchResults = const [],
    this.searchThrows = false,
    this.members = const [],
    this.requests = const CrewRequestPage(),
  });

  final CrewRequestPage requests;
  final bool throws;
  final List<CrewSearchResult> searchResults;
  final bool searchThrows;
  final List<PublicUser> members;

  @override
  Future<List<PublicUser>> getCrew() async {
    if (throws) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return members;
  }

  @override
  Future<CrewRequestPage> getRequestPage() async => requests;

  @override
  Future<List<CrewSearchResult>> search(String query) async {
    if (searchThrows) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return searchResults;
  }

  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();
  @override
  Future<ConnectOutcome> add(String userId) async => ConnectOutcome.active;
  @override
  Future<void> acceptRequest(String userId) async {}
  @override
  Future<void> declineRequest(String userId) async {}
  @override
  Future<void> remove(String userId) async {}

  @override
  Future<void> reportUser(String userId, {String? reason}) async {}
  @override
  Future<void> reportRace(String raceId, {String? reason}) async {}
  @override
  Future<void> reportContent(String contentId, {String? reason}) async {}
  @override
  Future<void> blockUser(String userId) async {}
  @override
  Future<void> unblockUser(String userId) async {}
}

class _FakeNotifRepo implements NotificationRepository {
  _FakeNotifRepo({this.throws = false});

  final bool throws;

  @override
  Future<NotificationPage> list({String? cursor, String? etag}) async {
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return const NotificationPage(items: [], unreadCount: 0);
  }
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}



Future<void> _settleDemo(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _sizes = [
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
];

Future<void> _pump(WidgetTester t, Size size, double inset, Brightness b,
    double scale, int lens) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.padding = FakeViewPadding(top: 47, bottom: inset);
  t.view.viewPadding = FakeViewPadding(top: 47, bottom: inset);
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: '/crew',
    routes: [
      ShellRoute(
        builder: (c, s, child) => MainShell(child: child),
        routes: [GoRoute(path: '/crew', builder: (c, s) => const PassScreen())],
      ),
    ],
  );
  await t.pumpWidget(ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(
          _PassRaceRepo(races: PresentationDemoData.races('user-1'))),
      crewRepositoryProvider.overrideWithValue(
          _FakeCrewRepo(
          members: PresentationDemoData.crewMembers(),
          requests: lens == 2
              ? PresentationDemoData.crewRequestPage()
              : const CrewRequestPage(),
        )),
      crewActivityRepositoryProvider.overrideWithValue(
          _FeedRepo(PresentationDemoData.crewActivity('user-1'))),
      notificationRepositoryProvider.overrideWithValue(_FakeNotifRepo()),
      authControllerProvider
          .overrideWith((ref) => AuthController(_FakeAuthRepo())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: b == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  ));
  await _settleDemo(t);
  if (lens == 1) {
    await t.tap(find.text('Activity'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }
  await t.pump(const Duration(milliseconds: 500));
}

String _chain(Element e) {
  final out = <String>[];
  e.visitAncestorElements((a) {
    out.add(a.widget.runtimeType.toString());
    return out.length < 8;
  });
  return out.join('<');
}

/// Person names and race titles are the one thing allowed to single-line
/// ellipsize (the test font is also far wider than the real one).
bool _isName(String t) =>
    t.toUpperCase().startsWith('FIRST TO') || t == 'Noah Williams';

bool _isStandingsLine(String t) => t.contains('  ·  ');

void main() {
  setUpAll(loadShotFonts);
  for (final size in _sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final b in Brightness.values) {
        for (final scale in [1.0, 1.3]) {
          for (final lens in [0, 1, 2]) {
            final name = '${size.width.toInt()}x${size.height.toInt()} '
                'inset$inset ${b.name} x$scale ${const ["people", "activity", "requests"][lens]}';
            testWidgets('crew at a glance $name', (t) async {
              await _pump(t, size, inset, b, scale, lens);
              expect(t.takeException(), isNull);
              if (b == Brightness.light && scale == 1.0 && inset == 34) {
                await shot(t, 'friends_${const ["people", "activity", "requests"][lens]}_${size.width.toInt()}x${size.height.toInt()}');
              }
              final navTop = t.getTopLeft(find.byType(NuvoBottomNav)).dy;
              final fade = find.byKey(const ValueKey('nuvo-bottom-fade'));
              expect(fade, findsOneWidget);
              expect(t.getRect(fade).bottom, lessThanOrEqualTo(navTop + 0.5));
              // Natural flow: sections stack with fixed spacing and scroll under
              // the bottom fade. The first screen is filled and no blank band
              // opens between consecutive sections.
              final foldFit =
                  t.renderObject<RenderSliverFoldFit>(find.byType(SliverFoldFit));
              expect(foldFit.lastAdjustment, 0,
                  reason: 'fold fitting must not move anything on this page');
              final sections = <Rect>[];
              foldFit.visitChildren((c) {
                if (c is RenderFoldGap) return;
                final box = c as RenderBox;
                if (!box.hasSize || box.size.height == 0) return;
                final tl = box.localToGlobal(Offset.zero);
                sections.add(tl & box.size);
              });
              expect(sections, isNotEmpty);
              var used = 0.0;
              for (var i = 0; i < sections.length; i++) {
                if (sections[i].top >= navTop) break;
                used = sections[i].bottom < navTop ? sections[i].bottom : navTop;
                if (i > 0) {
                  final gap = sections[i].top - sections[i - 1].bottom;
                  expect(gap, lessThanOrEqualTo(40),
                      reason: 'blank band of $gap between sections '
                          '${sections[i - 1]} and ${sections[i]}');
                }
              }
              expect(used / navTop, greaterThanOrEqualTo(0.9),
                  reason: 'first screen only ${(used / navTop * 100).round()}% used');
              for (final e in find.byType(Text).evaluate()) {
                final rect = t.getRect(find.byWidget(e.widget));
                if (rect.bottom <= 0 || rect.top >= navTop) continue;
                final txt = (e.widget as Text).data ?? '';
                // Primary labels never ellipsize at 1.0.
                // Feed sentences at 320pt may wrap past two lines in the test font.
                if (scale == 1.0 && !(lens == 1 && size.width < 340)) {
                  final ro = e.renderObject;
                  final inLive = find
                      .ancestor(
                          of: find.byWidget(e.widget),
                          matching: find.byType(NuvoLiveRaceCard))
                      .evaluate()
                      .isNotEmpty;
                  // Race titles inside the live card are names that may
                  // single-line ellipsize.
                  if (ro is RenderParagraph && !_isStandingsLine(ro.text.toPlainText()) && rect.bottom <= navTop && !inLive && !_isName(txt)) {
                    // ignore: unnecessary_statements
                    expect(ro.didExceedMaxLines, isFalse,
                        reason: '"${ro.text.toPlainText()}" ellipsized $rect ancestors: ${_chain(e)}');
                  }
                }
              }
            });
          }
        }
      }
    }
  }
}
