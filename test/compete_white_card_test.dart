import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'user-1',
      email: 'test@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}


Race _cameraRace({
  String id = 'race-1',
  String title = 'Pushup Race',
  int participantCount = 2,
  int progressPercent = 20,
  String status = 'active',
}) {
  final participants = <RaceParticipant>[
    RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: progressPercent,
      progressPercent: progressPercent,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    for (var i = 1; i < participantCount; i++)
      RaceParticipant(
        id: 'part-${i + 1}',
        userId: 'user-${i + 1}',
        displayName: 'Racer $i',
        progressValue: 10,
        progressPercent: 10,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
  ];
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: 100,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: participants,
  );
}

List<Race> _generateRaces(int count) {
  const activities = ['Pushup', 'Squat', 'Lunge', 'Plank', 'Jumping Jack'];
  return [
    for (var i = 0; i < count; i++)
      _cameraRace(
        id: 'race-$i',
        title: '${activities[i % activities.length]} Race ${i + 1}',
        participantCount: 2,
        progressPercent: 20 + (i % 50),
      ),
  ];
}

Widget _buildApp(RaceRepository repo, {bool dark = false}) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: const CompeteScreen(),
    ),
  );
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final pageBg = dark ? NuvoThemeColors.dark.page : NuvoColors.page;
    final fill = dark ? NuvoThemeColors.dark.panel : NuvoColors.navy;

    Finder card() => find.ancestor(
      of: find.textContaining('Your races'),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).boxShadow != null,
      ),
    );

    testWidgets('Your races card is navy ($name)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateRaces(5)), dark: dark),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(card().first);
      final d = box.decoration! as BoxDecoration;
      expect(d.color, fill);
      expect(
        (d.border! as Border).top.color,
        dark ? NuvoThemeColors.dark.border : NuvoColors.navy,
      );
      expect((d.border! as Border).top.width, 2);
      expect(d.boxShadow, isNotEmpty);
      expect(d.boxShadow!.first.blurRadius, 0);
      expect(d.boxShadow!.first.offset, isNot(Offset.zero));
      if (dark) expect(_ratio(fill, pageBg), greaterThanOrEqualTo(1.3));
    });

    for (final expand in [false, true]) {
      testWidgets('card text >= 4.5:1 on fill ($name, expanded=$expand)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _buildApp(_StubRaceRepo(_generateRaces(6)), dark: dark),
        );
        await tester.pumpAndSettle();
        if (expand) {
          await tester.tap(find.text('See all'));
          await tester.pumpAndSettle();
          expect(find.text('Show less'), findsOneWidget);
        }
        final texts = find.descendant(
          of: card().first,
          matching: find.byType(RichText),
        );
        var n = 0;
        for (final el in texts.evaluate()) {
          final rt = el.widget as RichText;
          final plain = rt.text.toPlainText();
          if (plain.trim().length <= 2) continue;
          final style = rt.text is TextSpan
              ? (rt.text as TextSpan).style
              : null;
          final color = style?.color;
          expect(color, isNotNull, reason: plain);
          // Pills sit on a translucent wash over the fill: composite it.
          final solid = Color.alphaBlend(color!, fill);
          expect(_ratio(solid, fill), greaterThanOrEqualTo(4.5), reason: plain);
          n++;
        }
        expect(n, greaterThan(3));
        expect(find.byType(RaceStatusPill), findsWidgets);
        // Same navy fill after expansion.
        expect(
          (tester.widget<Container>(card().first).decoration! as BoxDecoration)
              .color,
          fill,
        );
      });
    }
  }
}
