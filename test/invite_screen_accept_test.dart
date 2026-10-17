import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/invite_screen.dart';
import 'package:nuvo/features/social/social_providers.dart';

class _AuthRepo extends AuthRepository {
  _AuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'u1',
      email: 'a@example.com',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );
}

class _InviteRepo extends InviteRepository {
  _InviteRepo(this.onAccept)
    : super(InviteApi(), SecureTokenStore(), AuthApi());

  final Future<InviteAcceptResult> Function() onAccept;

  @override
  Future<InvitePreview> preview(String token) async =>
      InvitePreview.fromJson(const {
        'status': 'active',
        'kind': 'race_join',
        'requiresAuth': true,
        'preview': {
          'race': {'id': 'r1', 'title': 'Sunday pushups'},
        },
      });

  @override
  Future<InviteAcceptResult> accept(String token) => onAccept();
}

Future<void> _open(
  WidgetTester tester,
  Future<InviteAcceptResult> Function() onAccept,
) async {
  final router = GoRouter(
    initialLocation: '/invite/tok',
    routes: [
      GoRoute(
        path: '/invite/:token',
        builder: (c, s) => InviteScreen(token: s.pathParameters['token']!),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(_AuthRepo())),
      inviteRepositoryProvider.overrideWithValue(_InviteRepo(onAccept)),
    ],
  );
  addTearDown(container.dispose);
  container.read(authControllerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a non-JSON failure resets the button and shows a generic error',
      (tester) async {
    await _open(tester, () async => throw const FormatException('<html>429'));
    await tester.tap(find.text('Join race'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't accept this invite. Try again."), findsOneWidget);
    // Not stuck loading: the button is tappable again.
    expect(find.text('Join race'), findsOneWidget);
  });

  testWidgets('a closed race shows a clear message', (tester) async {
    await _open(
      tester,
      () async => InviteAcceptResult.fromJson(const {
        'ok': false,
        'status': 'closed',
      }),
    );
    await tester.tap(find.text('Join race'));
    await tester.pumpAndSettle();
    expect(find.text('This race has ended.'), findsOneWidget);
    expect(find.text('This invite could not be used.'), findsNothing);
  });
}
