import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
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
  Future<AuthUser?> restoreSession() async => const AuthUser(
    id: 'user-1',
    email: 'test@getnuvo.net',
    fullName: 'Test User',
    username: 'testuser',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  );
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;

  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: CompeteScreen()),
  );
}

void main() {
  group('Compete hierarchy (Batch 3)', () {
    testWidgets('Quick Start rows do not show "Editable camera race" sublabel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();

      // The dev-facing sublabel "Editable camera race" must not appear.
      expect(
        find.text('Editable camera race'),
        findsNothing,
        reason:
            'Quick Start sublabels should not expose dev-facing copy to users.',
      );
    });

    testWidgets('Start race CTA is wider than Join CTA (2:1 ratio)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();

      final startFinder = find.text('Start race');
      final joinFinder = find.text('Join');
      expect(startFinder, findsOneWidget);
      expect(joinFinder, findsOneWidget);

      // Both buttons are inside Expanded widgets in a Row.
      // Start race should have flex: 2, Join should have flex: 1.
      // Verify by checking the rendered widths.
      final startBox = tester.renderObject<RenderBox>(
        find.ancestor(
          of: startFinder,
          matching: find.byType(NuvoPrimaryButton),
        ),
      );
      final joinBox = tester.renderObject<RenderBox>(
        find.ancestor(of: joinFinder, matching: find.byType(NuvoOutlineButton)),
      );

      final startWidth = startBox.size.width;
      final joinWidth = joinBox.size.width;

      // Start race should be roughly 2x wider than Join (allowing for
      // the 10px SizedBox gap between them).
      expect(
        startWidth > joinWidth,
        isTrue,
        reason:
            'Start race CTA should be wider than Join CTA to establish hierarchy.',
      );
    });

    testWidgets('Hero does not show decorative blue dot when no finished races', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();

      // The "A fresh start line" status text should not appear when
      // finishedCount == 0 (we removed the decorative dot + redundant copy).
      expect(
        find.text('A fresh start line'),
        findsNothing,
        reason:
            'Decorative dot + "A fresh start line" copy should not appear when there are no finished races.',
      );
    });
  });
}
