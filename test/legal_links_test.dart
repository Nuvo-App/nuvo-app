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
import 'package:url_launcher/url_launcher.dart';

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
}

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
}
