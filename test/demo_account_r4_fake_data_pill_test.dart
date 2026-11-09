// R4 (docs/statements/demo-account.md): the fake-data pill is reachable for
// testing@getnuvo.net only.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'onboarding_v2/auth_visuals_support.dart';
import 'package:nuvo/features/shell/presentation/fake_data_pill.dart';

void main() {
  test('R4: fake-data pill shows for testing@getnuvo.net only', () {
    expect(showFakeDataPill('testing@getnuvo.net'), isTrue);
    expect(showFakeDataPill(' Testing@GetNuvo.net '), isTrue);
    expect(showFakeDataPill('someone@getnuvo.net'), isFalse);
    expect(showFakeDataPill('testing@gmail.com'), isFalse);
    expect(showFakeDataPill(''), isFalse);
    expect(showFakeDataPill(null), isFalse);
  });

  for (final c in [('testing@getnuvo.net', true), ('x@y.co', false)]) {
    testWidgets('R4: root layer shows pill for ${c.$1}: ${c.$2}', (t) async {
      final auth = FakeAuth()
        ..state = AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'u',
            email: c.$1,
            onboardingComplete: true,
            hasMemberPass: true,
            termsAccepted: true,
          ),
        );
      await t.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith((ref) => auth)],
          child: const MaterialApp(
            home: FakeDataPillLayer(child: Scaffold(body: Text('page'))),
          ),
        ),
      );
      await t.pump();
      expect(find.text('Fake data'), c.$2 ? findsOneWidget : findsNothing);
    });
  }
}
