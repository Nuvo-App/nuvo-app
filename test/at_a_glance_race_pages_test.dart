// At-a-glance contract for Race Detail and the proof-flow screens: at rest on
// first load nothing is bisected by the viewport bottom / safe inset / a
// scroll viewport edge, no primary label ellipsizes at 1.0, no overflow.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/theme/nuvo_responsive.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/race_detail/presentation/race_detail_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/board_moved_screen.dart';
import 'package:nuvo/features/races/presentation/invite_crew_screen.dart';
import 'package:nuvo/features/races/presentation/join_race_screen.dart';
import 'package:nuvo/features/races/presentation/proof_review_screen.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/race_settings_screen.dart';
import 'package:nuvo/features/races/presentation/submit_proof_screen.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/social_providers.dart';

import 'helpers/screenshot.dart';

const _me = AuthUser(
  id: 'user-1',
  email: 'akshay@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  fullName: 'Akshay Sanjai',
  username: 'akshay',
  motionTrainingConsent: true,
);

class _FakeTokenStore extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => null;
}

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(_me);
}

Race _race(
  String id,
  String title, {
  String mode = 'photo',
  String proofName = 'Maya Chen',
}) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'reps',
  customActivityName: 'Pushup',
  activityId: mode == 'ai' ? 'pushups' : null,
  proofRequirement: mode == 'ai' ? 'ai_check' : 'photo_video',
  proofMode: mode == 'ai' ? 'ai_check' : 'photo',
  verificationMethod: mode == 'ai' ? 'camera_pose' : 'photo_review',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  recentProofs: [
    RaceProof(
      id: 'p1',
      userId: 'u2',
      displayName: proofName,
      proofType: 'photo',
      value: 12,
      note: 'Set of twelve, felt strong',
      verificationStatus: 'pending',
      createdAt: '2026-01-02T00:00:00Z',
    ),
    const RaceProof(
      id: 'p2',
      userId: 'user-1',
      displayName: 'Akshay Sanjai',
      proofType: 'photo',
      value: 20,
      verificationStatus: 'verified',
      createdAt: '2026-01-01T12:00:00Z',
    ),
  ],
  participants: const [
    RaceParticipant(
      id: 'p1',
      userId: 'user-1',
      displayName: 'Akshay Sanjai',
      progressValue: 40,
      progressPercent: 40,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p2',
      userId: 'u2',
      displayName: 'Alexandria Montgomery-Santiago',
      progressValue: 62,
      progressPercent: 62,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p3',
      userId: 'u3',
      displayName: 'Noah Reyes',
      progressValue: 11,
      progressPercent: 11,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p4',
      userId: 'u4',
      displayName: 'Maya Chen',
      progressValue: 5,
      progressPercent: 5,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ],
);

final _races = [
  _race('race-1', 'Pushup Race'),
  _race('race-ai', 'Pushup Race', mode: 'ai'),
  _race(
    'race-review',
    'Pushup Race',
    proofName: 'Alexandria Montgomery-Santiago',
  ),
  _race(
    'race-long',
    'First to Complete 1000 Jumping Jacks Before Friday Night',
  ),
];

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<Race>> getRaces() => Future.value(_races);
  @override
  Future<List<PublicUser>> getCrew() async => const [
    PublicUser(id: 'u2', displayName: 'Alexandria Montgomery-Santiago', initials: 'AM'),
    PublicUser(id: 'u5', displayName: 'Sam Okafor', initials: 'SO'),
    PublicUser(id: 'u6', displayName: 'Priya Nair', initials: 'PN'),
  ];
  @override
  Future<String> createInviteCode(String id) async => 'RACE-42';
  @override
  Future<Race> getRaceDetail(String id) => Future.value(
    _races.firstWhere((r) => r.id == id, orElse: () => _races.first),
  );
}

class _SeededRaces extends RaceController {
  _SeededRaces()
    : super(
        _StubRaceRepo(),
        isPresentationDemo: () => false,
        presentationUserId: () => 'user-1',
        onMutated: () {},
      ) {
    state = RaceState(races: _races);
  }
  @override
  Future<void> loadRaces({bool force = false}) async {}
}

class _StubInviteRepo extends InviteRepository {
  _StubInviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintRaceInvite(String raceId) async =>
      const MintedInvite(
        token: 'tok-race',
        url: 'https://nuvo.app/i/tok-race',
        code: 'RACE-42',
        kind: 'race_join',
      );
}

final _surfaces = <String, Widget Function()>{
  'race-detail': () => const RaceDetailScreen(id: 'race-1'),
  'race-detail-long': () => const RaceDetailScreen(id: 'race-long'),
  'submit-proof-photo': () => const SubmitProofScreen(raceId: 'race-1'),
  'submit-proof-ai': () => const SubmitProofScreen(raceId: 'race-ai'),
  'join-race': () => const JoinRaceScreen(),
  'invite-crew': () => const InviteCrewScreen(raceId: 'race-1'),
  'race-settings': () => const RaceSettingsScreen(raceId: 'race-1'),
  'board-moved': () => const BoardMovedScreen(
    raceId: 'race-1',
    args: BoardMovedArgs(
      raceId: 'race-1',
      raceName: 'First to Complete 1000 Jumping Jacks Before Friday Night',
      value: 999999,
      unit: 'reps',
      rankBefore: 4,
      rankAfter: 2,
      peoplePassed: 2,
    ),
  ),
  'proof-review': () =>
      const ProofReviewScreen(raceId: 'race-review', proofId: 'p1'),
};

const _sizes = [
  (320.0, 568.0),
  (375.0, 667.0),
  (390.0, 844.0),
  (393.0, 852.0),
  (430.0, 932.0),
];

Widget _wrap(Widget child, {required bool dark, required double scale}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
      secureTokenStoreProvider.overrideWithValue(_FakeTokenStore()),
      raceRepositoryProvider.overrideWithValue(_StubRaceRepo()),
      raceControllerProvider.overrideWith((ref) => _SeededRaces()),
      inviteRepositoryProvider.overrideWithValue(_StubInviteRepo()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: NuvoTextScaleScope(child: c!),
      ),
      home: child,
    ),
  );
}

/// Walks every visible paragraph and returns human-readable problems.
List<String> _findCutOff(
  WidgetTester tester,
  double h,
  double inset,
  double scale,
) {
  final problems = <String>[];
  final hasFade =
      find.byKey(const ValueKey('nuvo-bottom-fade')).evaluate().isNotEmpty ||
      find.byType(ShaderMask).evaluate().isNotEmpty;
  final root = tester.binding.renderViews.first;
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize && o.size.height > 0) {
      final text = o.text.toPlainText();
      final box = o.localToGlobal(Offset.zero) & o.size;
      // Skip painted-off/offstage and zero-opacity is not detectable; require on-screen overlap.
      if (box.bottom > 0 && box.top < h && text.trim().isNotEmpty) {
        // Effective bottom edge: the screen, or the nearest enclosing scroll
        // viewport (content beyond it is clipped, i.e. cut off unless a
        // bottom fade softens it).
        var edge = h;
        var inViewport = false;
        RenderObject? p = o.parent;
        while (p != null) {
          if (p is RenderAbstractViewport && p is RenderBox) {
            final vb = p as RenderBox;
            final vr = vb.localToGlobal(Offset.zero) & vb.size;
            if (vr.bottom < edge) edge = vr.bottom;
            inViewport = true;
          }
          p = p.parent;
        }
        if (box.top < edge - 0.5 && box.bottom > edge + 0.5 && !hasFade) {
          problems.add('bisected at bottom edge: "$text"');
        }
        final limit = h - inset;
        if (!inViewport &&
            inset > 0 &&
            box.top < limit - 0.5 &&
            box.bottom > limit + 0.5) {
          problems.add('crosses safe inset: "$text"');
        }
        if (scale == 1.0 && o.didExceedMaxLines) {
          problems.add('ellipsized: "$text"');
        }
      }
    }
    o.visitChildren(visit);
  }

  visit(root);
  return problems;
}

void main() {
  setUpAll(() async {
    if (Platform.environment['SHOTS_DIR']?.isNotEmpty ?? false) {
      await loadShotFonts();
      return;
    }
    final bytes = ByteData.sublistView(
      await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
    );
    final manifest =
        const StandardMessageCodec().decodeMessage(
              await rootBundle.load('AssetManifest.bin'),
            )
            as Map<Object?, Object?>;
    for (final v in [
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      final key = 'test/fonts/Manrope-$v.ttf';
      manifest[key] = [
        {'asset': key},
      ];
    }
    final enc = const StandardMessageCodec().encodeMessage(manifest);
    for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
      final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') return enc;
          if (key.startsWith('test/fonts/Manrope')) return bytes;
          return null;
        });
  });

  for (final entry in _surfaces.entries) {
    testWidgets('at a glance: ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final (w, h) in _sizes) {
        for (final inset in [0.0, 34.0]) {
          for (final dark in [false, true]) {
            for (final scale in [1.0, 1.3]) {
              tester.view.physicalSize = Size(w, h);
              tester.view.devicePixelRatio = 1;
              tester.view.padding = FakeViewPadding(
                top: inset > 0 ? 44 : 20,
                bottom: inset,
              );
              await tester.pumpWidget(
                _wrap(entry.value(), dark: dark, scale: scale),
              );
              for (var i = 0; i < 12; i++) {
                await tester.pump(const Duration(milliseconds: 200));
              }
              if (!dark && scale == 1.0 && inset == 34) {
                await shot(
                  tester,
                  '${entry.key.replaceAll('-', '')}_${w.toInt()}x${h.toInt()}',
                );
              }
              final tag =
                  '${entry.key} ${w.toInt()}x${h.toInt()} inset=$inset '
                  '${dark ? 'dark' : 'light'} x$scale';
              final e = tester.takeException();
              if (e != null) {
                failures.add(
                  '$tag EXCEPTION ${e.toString().split('\n').first}',
                );
              }
              for (final p in _findCutOff(tester, h, inset, scale).toSet()) {
                failures.add('$tag $p');
              }
              await tester.pumpWidget(const SizedBox());
              await tester.pump();
            }
          }
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      if (failures.isNotEmpty) {
        // ignore: avoid_print
        print(failures.join('\n'));
      }
      expect(failures, isEmpty);
    });
  }
}
