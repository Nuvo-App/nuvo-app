import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/config/legal_links.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';
import 'package:nuvo/features/auth/presentation/welcome_auth_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:url_launcher/url_launcher.dart';

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
}

class _Races extends RaceRepository {
  _Races() : super(RaceApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<Race>> getRaces() => Future.value(const []);
}

Widget _app(Widget home) => ProviderScope(
  overrides: [
    raceRepositoryProvider.overrideWithValue(_Races()),
    authControllerProvider.overrideWith((ref) => AuthController(_Repo())),
  ],
  child: MaterialApp(home: home),
);

Widget _routed(Widget home) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith((ref) => AuthController(_Repo())),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => home)],
    ),
  ),
);

void main() {
  final launched = <Uri>[];
  final modes = <LaunchMode>[];
  var result = true;

  setUp(() {
    launched.clear();
    modes.clear();
    result = true;
    legalLaunchOverride = (uri, mode) async {
      launched.add(uri);
      modes.add(mode);
      return result;
    };
  });
  tearDown(() => legalLaunchOverride = null);

  test('the four legal URLs are exact', () {
    expect(LegalLinks.privacy, 'https://getnuvo.net/privacy/');
    expect(LegalLinks.terms, 'https://getnuvo.net/terms/');
    expect(
      LegalLinks.communityGuidelines,
      'https://getnuvo.net/community-guidelines/',
    );
    expect(LegalLinks.deleteAccount, 'https://getnuvo.net/delete-account/');
  });

  testWidgets('welcome footer shows both links and opens them externally', (
    tester,
  ) async {
    await tester.pumpWidget(_routed(const WelcomeAuthScreen()));
    await tester.pump();
    for (final label in ['Terms of Service', 'Privacy Policy']) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label), findsOneWidget);
      expect(tester.getSize(find.text(label)).height, greaterThan(0));
    }
    expect(find.text('By continuing, you agree to our'), findsOneWidget);

    await tester.ensureVisible(find.text('Terms of Service'));
    await tester.tap(find.text('Terms of Service'));
    await tester.pump();
    await tester.ensureVisible(find.text('Privacy Policy'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(launched, [LegalLinks.termsUri, LegalLinks.privacyUri]);
    expect(modes.toSet(), {LaunchMode.externalApplication});
  });

  testWidgets('email start screen carries the same footer', (tester) async {
    await tester.pumpWidget(_routed(const EmailStartScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('legal link tap targets are at least 44pt tall', (tester) async {
    await tester.pumpWidget(_routed(const WelcomeAuthScreen()));
    await tester.pump();
    final link = find.ancestor(
      of: find.text('Privacy Policy'),
      matching: find.byType(ConstrainedBox),
    );
    await tester.ensureVisible(find.text('Privacy Policy'));
    final box = tester.getSize(link.first);
    expect(box.height, greaterThanOrEqualTo(44));
  });

  testWidgets('Settings has Legal rows and Delete account', (tester) async {
    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pumpAndSettle();

    for (final label in [
      'Account',
      'Delete account',
      'Delete account on the web',
      'Legal',
      'Privacy Policy',
      'Terms of Service',
      'Community Guidelines',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    }

    final expected = {
      'Privacy Policy': LegalLinks.privacyUri,
      'Terms of Service': LegalLinks.termsUri,
      'Community Guidelines': LegalLinks.communityGuidelinesUri,
      'Delete account on the web': LegalLinks.deleteAccountUri,
    };
    for (final e in expected.entries) {
      await tester.ensureVisible(find.text(e.key));
      await tester.tap(find.text(e.key));
      await tester.pump();
    }
    expect(launched, expected.values.toList());
  });

  testWidgets('a failed launch says so', (tester) async {
    result = false;
    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Privacy Policy'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(find.text("Couldn't open the link. Try again."), findsOneWidget);
  });
}
