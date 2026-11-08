// Widget tests for the m2 legacy→v13 restyle: the level-up and achievement
// reward moments, the badge grid (earned + locked), and the email-verify
// screen — with shots.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/email_verify_screen.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/widgets/level_up_dialog.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';

import '../helpers/screenshot.dart';

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
  @override
  Future<void> startEmailAuth(String email) async {}
}

NuvoBadge _badge({
  required String key,
  required String name,
  String? category,
  String? iconKey,
  String? description,
  bool unlocked = false,
  bool featured = false,
  int? threshold,
  int progressValue = 0,
  String? unlockedAt,
}) => NuvoBadge(
  unlockId: 'test-$key',
  type: 'achievement',
  key: key,
  name: name,
  description: description,
  requiredLevel: 0,
  unlocked: unlocked,
  unlockedAt: unlockedAt,
  featured: featured,
  category: category,
  iconKey: iconKey,
  threshold: threshold,
  progressValue: progressValue,
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadShotFonts);

  group('Reward moments', () {
    testWidgets('level-up moment: LEVEL UP, rolling number, Nice', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showLevelUpMoment(
                    context,
                    level: 4,
                    badge: _badge(
                      key: 'first_move',
                      name: 'First Move',
                      category: 'racing',
                      iconKey: 'arrow_forward',
                      description: 'Submit your first proof.',
                      unlocked: true,
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('LEVEL UP'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.text('REWARD'), findsOneWidget);
      expect(find.text('First Move'), findsOneWidget);
      expect(find.text('Submit your first proof.'), findsOneWidget);
      expect(find.text('Nice'), findsOneWidget);
      await shot(tester, 'v13_level_up_moment');

      await tester.tap(find.text('Nice'));
      await tester.pumpAndSettle();
      expect(find.text('LEVEL UP'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('achievement moment: badge tile, name, Nice', (tester) async {
      _size(tester);
      final badge = _badge(
        key: 'hat_trick',
        name: 'Hat Trick',
        category: 'winning',
        iconKey: 'trophy_3',
        description: 'Win three races.',
        unlocked: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAchievementMoment(context, badge: badge),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('ACHIEVEMENT EARNED'), findsOneWidget);
      expect(find.text('Hat Trick'), findsOneWidget);
      expect(find.text('Win three races.'), findsOneWidget);
      expect(find.text('Nice'), findsOneWidget);
      await shot(tester, 'v13_achievement_moment');

      await tester.tap(find.text('Nice'));
      await tester.pumpAndSettle();
      expect(find.text('ACHIEVEMENT EARNED'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('NuvoBadgeGrid', () {
    testWidgets('earned + locked badges share the v13 tile', (tester) async {
      _size(tester);
      final badges = [
        _badge(
          key: 'first_move',
          name: 'First Move',
          category: 'racing',
          iconKey: 'arrow_forward',
          unlocked: true,
          featured: true,
        ),
        _badge(
          key: 'hat_trick',
          name: 'Hat Trick',
          category: 'winning',
          iconKey: 'trophy_3',
          threshold: 3,
          progressValue: 1,
        ),
        _badge(
          key: 'marathon',
          name: 'Marathon',
          category: 'performance',
          iconKey: 'num_26',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: NuvoBadgeGrid(badges: badges)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final b in badges) {
        expect(find.text(b.name), findsOneWidget);
      }
      expect(find.text('Earned'), findsOneWidget);
      // The locked tile with progress shows a bar, not the word.
      expect(find.text('Locked'), findsOneWidget);
      await shot(tester, 'v13_badge_grid');
      expect(tester.takeException(), isNull);
    });
  });

  group('EmailVerifyScreen', () {
    testWidgets('renders v13 chrome; resend confirms with a toast', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => AuthController(_FakeAuthRepo()),
            ),
          ],
          child: const MaterialApp(
            home: EmailVerifyScreen(email: 'test@getnuvo.net'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(
        find.text('Enter the 6-digit code we sent to test@getnuvo.net.'),
        findsOneWidget,
      );
      expect(find.text('Verify code'), findsOneWidget);
      expect(find.text('Resend code in 30s'), findsOneWidget);
      await shot(tester, 'v13_email_verify');

      // The cooldown is the real server window — run it down, resend, and
      // the confirmation is a v13 toast, not a SnackBar.
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('Resend code'), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(find.text('New code sent'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
