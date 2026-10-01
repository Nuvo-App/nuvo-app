// Onboarding "Build your profile" photo coverage — the avatar affordance
// must open the real pick/crop pipeline, preview the selection instantly,
// tolerate cancel/denied/upload-failure, and NEVER gate Continue on a photo.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nuvo/core/utils/photo_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/presentation/onboarding_screen.dart';

const _user = AuthUser(
  id: 'u1',
  email: 'member@example.com',
  onboardingComplete: false,
  hasMemberPass: false,
  termsAccepted: false,
);

/// Scripted repo — records the three-step upload pipeline so tests exercise
/// the real AuthController.uploadProfilePhoto instead of a stub.
class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());

  AuthUser user = _user;
  int uploadUrlCalls = 0;
  int uploadByteCalls = 0;
  String? savedPhotoUrl;
  bool removePhotoCalled = false;
  bool failUploadBytes = false;
  Completer<void>? uploadGate;

  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(user);

  @override
  Future<bool> checkUsername(String username) async => true;

  @override
  Future<void> acceptTerms() async {}

  @override
  Future<void> attestAge() async {}

  @override
  Future<void> saveProfile({
    String? fullName,
    String? username,
    bool? privateProfile,
    String? profilePhotoUrl,
    bool removePhoto = false,
  }) async {
    removePhotoCalled = removePhotoCalled || removePhoto;
    savedPhotoUrl = profilePhotoUrl;
    user = user.copyWith(
      fullName: fullName,
      username: username,
      profilePhotoUrl: profilePhotoUrl,
    );
  }

  @override
  Future<({String uploadUrl, String publicUrl, String key})>
  requestPhotoUploadUrl({
    required String fileName,
    required String contentType,
  }) async {
    uploadUrlCalls++;
    return (
      uploadUrl: 'https://storage.test/put',
      publicUrl: 'https://cdn.test/avatar.jpg',
      key: 'avatars/u1.jpg',
    );
  }

  @override
  Future<void> uploadBytesToSignedUrl(
    String signedUrl,
    Uint8List bytes,
    String contentType,
  ) async {
    uploadByteCalls++;
    if (uploadGate != null) await uploadGate!.future;
    if (failUploadBytes) throw const ApiException(500, 'upload failed');
  }

  @override
  Future<AuthUser> getMe() async => user;
}

/// Pump OnboardingScreen with a scripted picker and repo. [picker] receives
/// the requested source and returns the pick result.
Future<({ProviderContainer container, _Repo repo})> _pump(
  WidgetTester tester, {
  required _Repo repo,
  required Future<PhotoPickResult> Function(ImageSource) picker,
  bool withRouter = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
      photoPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);
  if (withRouter) {
    final router = GoRouter(
      initialLocation: '/onboarding/profile',
      routes: [
        GoRoute(
          path: '/onboarding/profile',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/onboarding/motion-consent',
          builder: (_, _) => const Scaffold(body: Text('motion-consent')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  } else {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return (container: container, repo: repo);
}

// A real 1×1 PNG so Image.memory can actually decode the preview.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

XFile _fakePhoto() =>
    XFile.fromData(_pngBytes, name: 'avatar.jpg', mimeType: 'image/jpeg');

Future<void> _pickViaSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('onboarding-avatar')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose from photos'));
  await tester.pumpAndSettle();
}

void main() {
  group('onboarding profile photo', () {
    testWidgets(
      'pick → instant local preview → real upload pipeline → saved URL',
      (tester) async {
        // TEST A/G — the full happy path through the production controller.
        final repo = _Repo();
        await _pump(
          tester,
          repo: repo,
          picker: (_) async => PhotoPickResult.picked(_fakePhoto()),
        );

        await _pickViaSheet(tester);

        // Local preview mounted immediately and the upload pipeline ran.
        expect(find.byKey(const ValueKey('avatar-local')), findsOneWidget);
        expect(repo.uploadUrlCalls, 1);
        expect(repo.uploadByteCalls, 1);
        expect(repo.savedPhotoUrl, 'https://cdn.test/avatar.jpg');
        expect(
          repo.user.profilePhotoUrl,
          'https://cdn.test/avatar.jpg',
          reason: 'getMe refresh must surface the saved avatar',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('picker cancel is silent — no error, screen unchanged', (
      tester,
    ) async {
      // TEST B — cancel must not look like a failure.
      final repo = _Repo();
      await _pump(
        tester,
        repo: repo,
        picker: (_) async => const PhotoPickResult.cancelled(),
      );

      await _pickViaSheet(tester);

      expect(find.byKey(const ValueKey('avatar-local')), findsNothing);
      expect(repo.uploadUrlCalls, 0);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.text('Open Settings'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'denied permission explains itself and offers Open Settings',
      (tester) async {
        // TEST C — denied is not a silent cancel.
        final repo = _Repo();
        await _pump(
          tester,
          repo: repo,
          picker: (_) async => const PhotoPickResult.denied(),
        );

        await _pickViaSheet(tester);

        expect(find.textContaining('Photo access is off'), findsOneWidget);
        expect(find.text('Open Settings'), findsOneWidget);
        expect(repo.uploadUrlCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'upload failure keeps the local preview and shows a recoverable error',
      (tester) async {
        // TEST E — failed upload: preview stays, error is honest, nothing
        // spins forever.
        final repo = _Repo()..failUploadBytes = true;
        await _pump(
          tester,
          repo: repo,
          picker: (_) async => PhotoPickResult.picked(_fakePhoto()),
        );

        await _pickViaSheet(tester);

        expect(find.byKey(const ValueKey('avatar-local')), findsOneWidget);
        expect(find.textContaining("Couldn't upload photo"), findsOneWidget);
        // The camera badge (not a spinner) is back — retry is possible.
        expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'leaving the screen mid-upload never setStates a dead widget',
      (tester) async {
        // TEST F — upload in flight, user navigates away, upload resolves.
        final repo = _Repo()..uploadGate = Completer<void>();
        await _pump(
          tester,
          repo: repo,
          picker: (_) async => PhotoPickResult.picked(_fakePhoto()),
          withRouter: true,
        );

        await tester.tap(find.byKey(const ValueKey('onboarding-avatar')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose from photos'));
        await tester.pump();
        await tester.pump();

        // Navigate away while the upload is blocked.
        final ctx = tester.element(find.byType(OnboardingScreen));
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('away')),
          ),
        );
        await tester.pumpAndSettle();

        repo.uploadGate!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Continue is never gated on a photo — setup completes without one',
      (tester) async {
        // TEST K — photo optional: name + username + legal alone enable
        // Continue and finish the step.
        final repo = _Repo();
        await _pump(
          tester,
          repo: repo,
          picker: (_) async => const PhotoPickResult.failed(),
          withRouter: true,
        );

        await tester.enterText(
          find.byType(TextField).at(0),
          'Nuvo Review',
        );
        await tester.enterText(
          find.byType(TextField).at(1),
          'nuvo_review',
        );
        // Wait out the username-availability debounce.
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
        for (final box in find.byType(Checkbox).evaluate().toList()) {
          await tester.ensureVisible(find.byWidget(box.widget));
          await tester.pump();
          await tester.tap(find.byWidget(box.widget));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('motion-consent'), findsOneWidget);
        expect(repo.uploadUrlCalls, 0, reason: 'no photo — no upload attempt');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
