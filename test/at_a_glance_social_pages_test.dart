// At-a-glance contract for the social / auth / onboarding pages: at rest on
// first load no text line is bisected by the viewport bottom, no label
// ellipsizes at text scale 1.0, and nothing overflows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';
import 'package:nuvo/features/auth/presentation/email_verify_screen.dart';
import 'package:nuvo/features/auth/presentation/welcome_auth_screen.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/presentation/public_badges_screen.dart';
import 'package:nuvo/features/crew/presentation/public_profile_screen.dart';
import 'package:nuvo/features/onboarding/presentation/onboarding_screen.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/add_crew_screen.dart';
import 'package:nuvo/features/social/presentation/invite_screen.dart';
import 'package:nuvo/features/social/presentation/my_nuvo_screen.dart';
import 'package:nuvo/features/social/presentation/my_qr_sheet.dart';
import 'package:nuvo/features/social/presentation/race_share_sheet.dart';
import 'package:nuvo/features/social/social_providers.dart';

const _passInfo = PassInfo(
  memberId: 'NUVO-001',
  passSlug: 'maya',
  shareUrl: 'https://getnuvo.net/p/maya',
);

class _Repo extends AuthRepository {
  _Repo({required this.demo, this.onboarding = false})
    : super(AuthApi(), SecureTokenStore());
  final bool demo;
  final bool onboarding;
  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(
    AuthUser(
      id: 'demo-viewer-1',
      email: 'demo-viewer@example.com',
      isDemo: demo,
      fullName: 'Maya Chen',
      username: 'maya',
      onboardingComplete: !onboarding,
      hasMemberPass: !onboarding,
      termsAccepted: !onboarding,
    ),
  );
  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
  @override
  Future<bool> checkUsername(String username) async => true;
}

class _InviteRepo extends InviteRepository {
  _InviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintMyCrewInvite() async => const MintedInvite(
    token: 't',
    url: 'https://getnuvo.net/i/t',
    kind: 'crew_connect',
  );
  @override
  Future<MintedInvite> mintRaceInvite(String raceId) async =>
      const MintedInvite(
        token: 't',
        url: 'https://getnuvo.net/i/t',
        kind: 'race',
      );
}

class _Case {
  _Case(this.name, this.build, {this.onboarding = false});
  final String name;
  final Widget Function() build;
  final bool onboarding;
}

Widget _sheetHost(Future<void> Function(BuildContext) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

final _cases = <_Case>[
  _Case('my code', () => const MyNuvoScreen()),
  _Case('add crew', () => const AddCrewScreen()),
  _Case('invite', () => const InviteScreen(token: 'tok')),
  _Case('public profile', () => const PublicProfileScreen(userId: 'demo-1')),
  _Case('public badges', () => const PublicBadgesScreen(userId: 'demo-1')),
  _Case('welcome', () => const WelcomeAuthScreen()),
  _Case('welcome login', () => const WelcomeAuthScreen(initialLogin: true)),
  _Case('email start', () => const EmailStartScreen()),
  _Case(
    'email verify',
    () => const EmailVerifyScreen(email: 'maya.chen@example.com'),
  ),
  _Case('onboarding', () => const OnboardingScreen(), onboarding: true),
];

const _sizes = [
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
];

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required Size size,
  required double inset,
  required bool dark,
  required double scale,
  bool onboarding = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(
    top: inset > 0 ? 47 : 20,
    bottom: inset,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: inset > 0 ? 47 : 20,
    bottom: inset,
  );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inviteRepositoryProvider.overrideWithValue(_InviteRepo()),
        crewRepositoryProvider.overrideWithValue(_NoCrew()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(_Repo(demo: true, onboarding: onboarding)),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => home)],
        ),
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

class _NoCrew extends CrewRepository {
  _NoCrew() : super(CrewApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<PublicUser>> getCrew() async => const [];
  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();
}

/// Problems for every visible paragraph: bisected by the viewport bottom, or
/// (at scale 1.0) ellipsized.
List<String> _audit(
  WidgetTester tester,
  Size size,
  double scale, {
  bool hasFade = false,
}) {
  final out = <String>[];
  final h = size.height;
  final root = tester.binding.rootElement!;
  void visit(Element e) {
    final w = e.widget;
    if (w is Offstage && w.offstage) return;
    final ro = e.renderObject;
    if (w is RichText && ro is RenderParagraph && ro.attached && ro.hasSize) {
      final box = ro;
      final tl = box.localToGlobal(Offset.zero);
      final r = tl & box.size;
      final text = box.text.toPlainText();
      final visible =
          r.width > 0 &&
          r.height > 0 &&
          r.top < h &&
          r.left < size.width &&
          r.right > 0;
      if (visible && text.trim().isNotEmpty) {
        if (r.bottom > h + 0.5 && !hasFade) {
          out.add('bisected "$text" bottom=${r.bottom} h=$h');
        }
        if (scale == 1.0 && box.didExceedMaxLines) {
          out.add('ellipsized "$text" size=${box.size}');
        }
      }
    }
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  return out;
}

void main() {
  setUpAll(() async {
    final bytes = ByteData.sublistView(
      await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
    );
    for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
      final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final c in _cases) {
    for (final size in _sizes) {
      for (final inset in [0.0, 34.0]) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 1.3]) {
            testWidgets(
              '${c.name} ${size.width.toInt()}x${size.height.toInt()} inset$inset ${dark ? 'dark' : 'light'} x$scale',
              (tester) async {
                await _pump(
                  tester,
                  c.build(),
                  size: size,
                  inset: inset,
                  dark: dark,
                  scale: scale,
                  onboarding: c.onboarding,
                );
                expect(tester.takeException(), isNull);
                final fade = find
                    .byKey(const ValueKey('nuvo-bottom-fade'))
                    .evaluate()
                    .isNotEmpty;
                final problems = _audit(tester, size, scale, hasFade: fade);
                expect(problems, isEmpty);
              },
            );
          }
        }
      }
    }
  }

  for (final dark in [false, true]) {
    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        for (final entry in <String, Future<void> Function(BuildContext)>{
          'qr sheet': (c) =>
              showMyQrSheet(c, displayName: 'Maya Chen', memberId: 'NUVO-001'),
          'race share': (c) => showRaceShareSheet(
            c,
            raceId: 'r1',
            raceTitle: 'Morning push-ups',
          ),
        }.entries) {
          testWidgets(
            '${entry.key} ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'} x$scale',
            (tester) async {
              await _pump(
                tester,
                _sheetHost(entry.value),
                size: size,
                inset: 34,
                dark: dark,
                scale: scale,
              );
              await tester.tap(find.text('open'));
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 150));
              }
              expect(tester.takeException(), isNull);
              expect(_audit(tester, size, scale), isEmpty);
            },
          );
        }
      }
    }
  }
}
