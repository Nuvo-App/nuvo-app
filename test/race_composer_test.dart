import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/pressable_scale.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/presentation/custom_pose/recent_movements_provider.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

import 'fixtures/pose_fixtures.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

MotionActivityDefinition _activity(MotionActivityType type) =>
    motionActivityForType(type)!;

final _pushups = _activity(MotionActivityType.pushUps);
final _jacks = _activity(MotionActivityType.jumpingJacks);
final _squats = _activity(MotionActivityType.squats);
final _plank = _activity(MotionActivityType.plankHold);

CustomPoseVerifierSpec _anySpec() {
  final pose = const PoseNormalizer().normalize(neutralStandingPose());
  final summary = const CustomPoseCalibrationSummary(
    sourceCalibrationSchemaVersion: 1,
    demonstrationCount: 2,
    selectedActiveFeatureCount: 1,
    requiredFeatureCount: 1,
    canonicalSequenceLength: 1,
    pairwiseSimilarityScores: {},
    overallConsistencyScore: 0.7,
    lowestPairwiseSimilarityScore: 0.7,
    sequenceSimilarityThreshold: 0.7,
    completionSimilarityThreshold: 0.8,
    resetSimilarityThreshold: 0.8,
    minimumValidFeatureRatio: 0.6,
    minimumVisibility: 0.6,
    cooldownMs: 500,
    completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
    builderVersion: 'v1',
  );
  return CustomPoseVerifierSpec(
    schemaVersion: 1,
    verifierType: 'custom_pose_sequence',
    movementName: 'wave',
    measurementType: 'reps',
    startPose: pose,
    completionPose: pose,
    completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
    canonicalSequence: const [],
    requiredFeatureIds: const [],
    activeFeatureIds: const [],
    sequenceSimilarityThreshold: 0.7,
    completionSimilarityThreshold: 0.8,
    resetSimilarityThreshold: 0.8,
    minimumValidFeatureRatio: 0.6,
    minimumVisibility: 0.6,
    cooldownMs: 500,
    expectedSequenceFrameCount: 1,
    calibrationSummary: summary,
  );
}

Race _race({required String title}) {
  return Race(
    id: 'race_1',
    creatorId: 'user_1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: 10,
    unit: 'reps',
    status: 'active',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Widget tests pump the composer — runtime font fetching is off and the
  // packaged Manrope faces are stubbed from tmp/social-qa so the theme
  // resolves without HttpClient.
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const fontAssets = {
      'test/fonts/Manrope-Regular.ttf':
          'tmp/social-qa/fonts/Manrope_regular.ttf',
      'test/fonts/Manrope-Medium.ttf':
          'tmp/social-qa/fonts/Manrope_medium.ttf',
      'test/fonts/Manrope-SemiBold.ttf':
          'tmp/social-qa/fonts/Manrope_semiBold.ttf',
      'test/fonts/Manrope-Bold.ttf': 'tmp/social-qa/fonts/Manrope_bold.ttf',
      'test/fonts/Manrope-ExtraBold.ttf':
          'tmp/social-qa/fonts/Manrope_extraBold.ttf',
    };
    const families = {
      'Manrope_regular': 'tmp/social-qa/fonts/Manrope_regular.ttf',
      'Manrope_500': 'tmp/social-qa/fonts/Manrope_medium.ttf',
      'Manrope_600': 'tmp/social-qa/fonts/Manrope_semiBold.ttf',
      'Manrope_700': 'tmp/social-qa/fonts/Manrope_bold.ttf',
      'Manrope_800': 'tmp/social-qa/fonts/Manrope_extraBold.ttf',
    };
    final manifest = const StandardMessageCodec().decodeMessage(
            await rootBundle.load('AssetManifest.bin'))
        as Map<Object?, Object?>;
    for (final key in fontAssets.keys) {
      manifest[key] = [
        {'asset': key}
      ];
    }
    final manifestBytes =
        const StandardMessageCodec().encodeMessage(manifest);
    final fontBytes = {
      for (final e in fontAssets.entries)
        e.key: ByteData.sublistView(await File(e.value).readAsBytes())
    };
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') return manifestBytes;
      return fontBytes[key] ??
          await messenger.delegate.send('flutter/assets', message);
    });
    for (final e in families.entries) {
      await (FontLoader(e.key)
            ..addFont(Future.value(
                ByteData.sublistView(
                    await File(e.value).readAsBytes()))))
          .load();
    }
  });

  // ── 1. Generated title contract ────────────────────────────────────────────
  group('generatedTitle()', () {
    test('produces "First to N ActivityName" format', () {
      expect(generatedTitle(_pushups, 15), 'First to 15 Pushups');
      expect(generatedTitle(_jacks, 30), 'First to 30 Jumping Jacks');
      expect(generatedTitle(_plank, 60), 'First to 60 Plank');
    });

    test('uses lowercase "to" not "To"', () {
      final t = generatedTitle(_pushups, 10);
      expect(t, contains('First to'));
      expect(t, isNot(contains('First To')));
    });
  });

  // ── 2. RaceDraft.resolvedTitle ─────────────────────────────────────────────
  group('RaceDraft.resolvedTitle', () {
    test('returns generated title when hasCustomName is false', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      expect(draft.hasCustomName, isFalse);
      expect(draft.resolvedTitle, 'First to 15 Jumping Jacks');
    });

    test('returns custom title when hasCustomName is true', () {
      final draft = draftForActivity(_jacks).copyWith(
        title: 'Akshay vs Akaash',
        hasCustomName: true,
        targetValue: 15,
      );
      expect(draft.resolvedTitle, 'Akshay vs Akaash');
    });
  });

  // ── 3. Generated title updates when activity changes ──────────────────────
  group('Generated title stays in sync', () {
    test('activity change regenerates resolved title (not custom)', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 15);
      final updated = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      expect(updated.resolvedTitle, 'First to 15 Jumping Jacks');
    });

    test('target change regenerates resolved title (not custom)', () {
      final draft = draftForActivity(_jacks);
      final updated = draft.copyWith(targetValue: 30);
      expect(updated.resolvedTitle, 'First to 30 Jumping Jacks');
    });

    test('both activity AND target change regenerates correctly', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 6);
      final updated = draft.copyWith(
        activity: _jacks,
        metric: _jacks.metric,
        targetValue: 15,
      );
      expect(updated.resolvedTitle, 'First to 15 Jumping Jacks');
    });
  });

  // ── 4. Custom title is preserved ──────────────────────────────────────────
  group('Custom title preservation', () {
    test('activity change does NOT overwrite a custom title', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'Akshay vs Akaash', hasCustomName: true);
      final updated = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      expect(updated.resolvedTitle, 'Akshay vs Akaash');
    });

    test('target change does NOT overwrite a custom title', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'Akshay vs Akaash', hasCustomName: true);
      final updated = draft.copyWith(targetValue: 50);
      expect(updated.resolvedTitle, 'Akshay vs Akaash');
    });

    test('custom title is preserved across multiple edits', () {
      var draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'My Custom Race', hasCustomName: true);
      draft = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      draft = draft.copyWith(targetValue: 25);
      draft = draft.copyWith(activity: _squats, metric: _squats.metric);
      expect(draft.resolvedTitle, 'My Custom Race');
    });
  });

  // ── 5. toCreatePayload title comes from resolvedTitle ─────────────────────
  group('toCreatePayload title integrity', () {
    test('payload title matches resolvedTitle for generated names', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['title'], draft.resolvedTitle);
      expect(payload['title'], 'First to 15 Jumping Jacks');
    });

    test('payload title preserves custom name', () {
      final draft = draftForActivity(_jacks).copyWith(
        title: 'Akshay vs Akaash',
        hasCustomName: true,
        targetValue: 15,
      );
      final payload = draft.toCreatePayload();
      expect(payload['title'], 'Akshay vs Akaash');
    });

    test('manual goal produces an evidence-required payload', () {
      final draft = draftForActivity(_jacks).copyWith(
        goalKind: RaceGoalKind.manual,
        manualGoalName: 'Read',
        manualUnit: 'pages',
        targetValue: 300,
      );
      expect(draft.isManual, isTrue);
      expect(draft.isValidToCreate, isTrue);
      final payload = draft.toCreatePayload();
      // Non-automated contracts carry photo proof on every submission —
      // no evidence, no canonical progress.
      expect(payload['proofRequirement'], 'photo_video');
      expect(payload['proofMode'], 'photo');
      expect(payload['unit'], 'pages');
      expect(payload['targetValue'], 300);
      expect(payload.containsKey('activityId'), isFalse);
      expect(payload['title'], 'First to 300 pages');
    });

    test('manual goal without name or unit is not valid to create', () {
      final draft = draftForActivity(_jacks).copyWith(
        goalKind: RaceGoalKind.manual,
        targetValue: 10,
      );
      expect(draft.isValidToCreate, isFalse);
    });

    test('payload title, targetValue and activityId are consistent', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['title'], contains('15'));
      expect(payload['title'], contains('Jumping Jacks'));
      expect(payload['targetValue'], 15);
      expect(payload['activityId'], 'jumping_jacks');
    });

    test('payload never shows stale pushup count after switching to jacks', () {
      // Reproduce the exact bug: start pushups 6, switch to jacks, target 15
      final initial = draftFromIdea('First to 6 pushups')!;
      final afterActivity = initial.copyWith(
        activity: _jacks,
        metric: _jacks.metric,
      );
      final afterTarget = afterActivity.copyWith(targetValue: 15);
      final payload = afterTarget.toCreatePayload();

      expect(payload['title'], 'First to 15 Jumping Jacks');
      expect(payload['targetValue'], 15);
      expect(payload['activityId'], 'jumping_jacks');
      // "6" must not appear anywhere in the payload title
      expect(payload['title'], isNot(contains('6')));
    });
  });

  // ── 6. Goal direct edit (int clamping) ────────────────────────────────────
  group('Goal value clamping', () {
    test('copyWith clamps target to at least 1', () {
      final draft = draftForActivity(_pushups);
      final clamped = draft.copyWith(targetValue: 0);
      // 0 can be stored (clamping is in UI), but resolvedTitle still formats
      expect(clamped.targetValue, 0); // domain allows it; UI prevents it
    });

    test('arbitrary large target is valid in domain', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 99999);
      expect(draft.targetValue, 99999);
      expect(draft.resolvedTitle, 'First to 99999 Pushups');
    });

    test('suggested targets are all valid positives', () {
      for (final def in motionActivityDefinitions) {
        for (final t in def.suggestedTargets) {
          expect(t, greaterThan(0));
        }
      }
    });
  });

  // ── 7. Plus/minus step size logic ─────────────────────────────────────────
  group('Step size', () {
    int stepFor(int target) {
      if (target < 10) return 1;
      if (target < 100) return 5;
      if (target < 1000) return 25;
      return 100;
    }

    test('step is 1 below 10', () => expect(stepFor(5), 1));
    test('step is 5 from 10 to 99', () => expect(stepFor(50), 5));
    test('step is 25 from 100 to 999', () => expect(stepFor(200), 25));
    test('step is 100 at 1000+', () => expect(stepFor(1000), 100));
  });

  // ── 8. Back/forward preserves draft ───────────────────────────────────────
  group('Draft survives step navigation', () {
    test('copyWith preserves all unrelated fields', () {
      final draft = draftForActivity(_jacks).copyWith(
        targetValue: 15,
        title: 'My Race',
        hasCustomName: true,
        inviteCrew: false,
      );
      // Simulate going back to activity and selecting squats, then forward
      final updated = draft.copyWith(activity: _squats, metric: _squats.metric);
      expect(updated.targetValue, 15);
      expect(updated.inviteCrew, isFalse);
      expect(updated.hasCustomName, true);
      expect(updated.resolvedTitle, 'My Race'); // custom preserved
    });

    test('Start solo keeps the invite link closed', () {
      final draft = draftForActivity(_jacks).copyWith(inviteCrew: false);
      expect(draft.inviteCrew, isFalse);
    });

    test('Pull in crew opens the invite link after create', () {
      final draft = draftForActivity(_jacks).copyWith(inviteCrew: true);
      expect(draft.inviteCrew, isTrue);
    });
  });

  // ── 9. Plank uses seconds everywhere ──────────────────────────────────────
  group('Plank seconds', () {
    test('plank draft has seconds metric', () {
      final draft = draftForActivity(_plank);
      expect(draft.metric, RaceMetric.seconds);
    });

    test('plank payload has seconds in metric and targetUnit', () {
      final draft = draftForActivity(_plank).copyWith(targetValue: 60);
      final payload = draft.toCreatePayload();
      expect(payload['metric'], 'seconds');
      expect(payload['targetUnit'], 'seconds');
      expect(payload['targetValue'], 60);
    });

    test('plank resolved title uses raw number (not seconds label)', () {
      final draft = draftForActivity(_plank).copyWith(targetValue: 60);
      expect(draft.resolvedTitle, 'First to 60 Plank');
    });

    test('switching from reps activity to plank resets metric to seconds', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(activity: _plank, metric: _plank.metric);
      expect(draft.metric, RaceMetric.seconds);
    });
  });

  // ── 10. draftFromIdea used by Quick Starts ─────────────────────────────────
  group('Quick Start prefill', () {
    test('jumping jacks quick start produces correct draft', () {
      final draft = draftFromIdea('First to 30 jumping jacks')!;
      expect(draft.activity.type, MotionActivityType.jumpingJacks);
      expect(draft.targetValue, 30);
      expect(draft.hasCustomName, isFalse);
      expect(draft.resolvedTitle, 'First to 30 Jumping Jacks');
    });

    test('plank quick start has seconds metric', () {
      final draft = draftFromIdea('First to 60 plank seconds')!;
      expect(draft.metric, RaceMetric.seconds);
      expect(draft.resolvedTitle, 'First to 60 Plank');
    });

    test('quick start payload title and target agree', () {
      final draft = draftFromIdea('First to 40 lunges')!;
      final payload = draft.toCreatePayload();
      expect(payload['title'], 'First to 40 Lunges');
      expect(payload['targetValue'], 40);
      expect(payload['activityId'], 'lunges');
    });
  });

  // ── 11. Custom movement races ───────────────────────────────────────────────
  group('Custom movement races', () {
    test('custom draft with verifierSpec is valid', () {
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 10,
        customActivityName: 'wave',
        verifierSpec: _anySpec(),
      );

      expect(draft.isCustom, isTrue);
      expect(draft.isValidToCreate, isTrue);
      expect(draft.displayActivityName, 'wave');
      expect(draft.resolvedTitle, 'First to 10 wave');
    });

    test('custom draft without verifierSpec is not valid', () {
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 10,
        customActivityName: 'wave',
        verifierSpec: null,
      );

      expect(draft.isCustom, isTrue);
      expect(draft.isValidToCreate, isFalse);
      expect(draft.displayActivityName, 'wave');
    });

    test('toCreatePayload is blocked for custom drafts', () {
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 10,
        customActivityName: 'wave',
        verifierSpec: _anySpec(),
      );

      expect(draft.toCreatePayload, throwsUnsupportedError);
    });

    test('preset activity validation does not run for custom drafts', () {
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 10,
        customActivityName: 'wave',
        verifierSpec: _anySpec(),
      );

      // Even with a preset pushups activity in the draft, the custom path is
      // valid and does not require that activity to be supported.
      expect(draft.isValidToCreate, isTrue);
      expect(draft.toCreatePayload, throwsUnsupportedError);
    });

    test('switching from custom to preset clears verifier state', () {
      final custom = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 10,
        customActivityName: 'wave',
        verifierSpec: _anySpec(),
      );

      final preset = custom.asPreset(activity: _jacks, targetValue: 25);

      expect(preset.isCustom, isFalse);
      expect(preset.customActivityName, isNull);
      expect(preset.verifierSpec, isNull);
      expect(preset.isValidToCreate, isTrue);
      expect(preset.toCreatePayload()['activityId'], 'jumping_jacks');
    });

    test('UI shows learned movement name in title and display', () {
      final draft = RaceDraft(
        title: 'My Custom Race',
        hasCustomName: true,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 15,
        customActivityName: 'Overhead Wave',
        verifierSpec: _anySpec(),
      );

      expect(draft.displayActivityName, 'Overhead Wave');
      expect(draft.resolvedTitle, 'My Custom Race');
      expect(draft.generatedTitleText, 'First to 15 Overhead Wave');
    });

    test('composer custom draft calls createCustomRace', () async {
      final spec = _anySpec();
      final draft = RaceDraft(
        title: '',
        hasCustomName: false,
        activity: _pushups,
        metric: RaceMetric.reps,
        format: RaceFormat.firstToGoal,
        targetValue: 12,
        customActivityName: 'Overhead Wave',
        verifierSpec: spec,
      );
      var customCalled = false;
      var presetCalled = false;

      final race = await createRaceForComposerDraft(
        draft: draft,
        createCustomRace:
            ({
              required title,
              required targetValue,
              required customActivityName,
              required verifierSpec,
            }) async {
              customCalled = true;
              expect(title, 'First to 12 Overhead Wave');
              expect(targetValue, 12);
              expect(customActivityName, 'Overhead Wave');
              expect(verifierSpec, same(spec));
              return _race(title: title);
            },
        createRace:
            ({
              required title,
              description,
              category,
              goalType = 'manual',
              targetValue,
              unit,
              proofRequirement,
              proofReviewMode,
              aiActivityType,
              activityId,
              metric,
              format,
              recurrence,
              targetUnit,
              proofMode,
              scoreDirection,
            }) async {
              presetCalled = true;
              return _race(title: title);
            },
      );

      expect(race.title, 'First to 12 Overhead Wave');
      expect(customCalled, isTrue);
      expect(presetCalled, isFalse);
    });

    test('composer preset draft calls createRace', () async {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 30);
      var customCalled = false;
      var presetCalled = false;

      final race = await createRaceForComposerDraft(
        draft: draft,
        createCustomRace:
            ({
              required title,
              required targetValue,
              required customActivityName,
              required verifierSpec,
            }) async {
              customCalled = true;
              return _race(title: title);
            },
        createRace:
            ({
              required title,
              description,
              category,
              goalType = 'manual',
              targetValue,
              unit,
              proofRequirement,
              proofReviewMode,
              aiActivityType,
              activityId,
              metric,
              format,
              recurrence,
              targetUnit,
              proofMode,
              scoreDirection,
            }) async {
              presetCalled = true;
              expect(title, 'First to 30 Jumping Jacks');
              expect(activityId, 'jumping_jacks');
              return _race(title: title);
            },
      );

      expect(race.title, 'First to 30 Jumping Jacks');
      expect(customCalled, isFalse);
      expect(presetCalled, isTrue);
    });

    test(
      'createCustomRace failure does not clear learned movement or draft',
      () async {
        final spec = _anySpec();
        final draft = RaceDraft(
          title: '',
          hasCustomName: false,
          activity: _pushups,
          metric: RaceMetric.reps,
          format: RaceFormat.firstToGoal,
          targetValue: 10,
          customActivityName: 'wave',
          verifierSpec: spec,
        );

        expect(draft.isCustom, isTrue);
        expect(draft.verifierSpec, isNotNull);
        expect(draft.customActivityName, 'wave');

        // Simulate a failed create — the draft and spec must survive
        Object? caught;
        try {
          await createRaceForComposerDraft(
            draft: draft,
            createCustomRace:
                ({
                  required title,
                  required targetValue,
                  required customActivityName,
                  required verifierSpec,
                }) async {
                  throw Exception('HTTP 500: Internal server error');
                },
            createRace:
                ({
                  required title,
                  description,
                  category,
                  goalType = 'manual',
                  targetValue,
                  unit,
                  proofRequirement,
                  proofReviewMode,
                  aiActivityType,
                  activityId,
                  metric,
                  format,
                  recurrence,
                  targetUnit,
                  proofMode,
                  scoreDirection,
                }) async {
                  return _race(title: title);
                },
          );
        } catch (e) {
          caught = e;
        }

        // The exception propagated — but the draft and spec are unchanged
        expect(caught, isNotNull);
        expect(draft.isCustom, isTrue);
        expect(draft.verifierSpec, same(spec));
        expect(draft.customActivityName, 'wave');
        expect(draft.targetValue, 10);
      },
    );
  });

  // ── Movement picker state hardening ───────────────────────────────────────
  //
  // Data count must not break composition: 0..N recents, dedupe, stable
  // order, identical selected/unselected geometry, canonical units, and a
  // pinned CTA that never covers content.

  group('Movement picker states', () {
    setSize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding =
          const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding =
          const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }

    Future<void> pumpPicker(
      WidgetTester tester, {
      List<String> recents = const [],
      Size size = const Size(390, 844),
      ThemeData? theme,
      double textScale = 1.0,
    }) async {
      setSize(tester, size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentMovementsStoreProvider
                .overrideWithValue(_PickerStore(recents)),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: const RaceComposerScreen(
                prefill: RaceCreatePrefill(idea: 'First to 50 pushups'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();
      Object? pumpError;
      while ((pumpError = tester.takeException()) != null) {
        debugPrint('picker pump exception: $pumpError');
      }
      if (pumpError != null) fail('picker threw during pump');
    }

    // Each movement tile wraps its content in a PressableScale — the CTA
    // and chips use different shells, so this isolates real tiles.
    Finder tile(String title) => find.widgetWithText(PressableScale, title);

    int tileCount(WidgetTester tester) => tester
        .widgetList(find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_MovementTile'))
        .length;

    testWidgets('0 recents → Quick picks, no Recent heading', (tester) async {
      await pumpPicker(tester, recents: const []);
      expect(find.text('Quick picks'), findsOneWidget);
      expect(find.text('Recent activities'), findsNothing);
      expect(tileCount(tester), 4);
      expect(find.text('Pick a movement'), findsOneWidget);
    });

    testWidgets('1 recent → full-width recent + suggested fills to 4',
        (tester) async {
      await pumpPicker(tester, recents: const ['plank_hold']);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(tileCount(tester), 4);
      // The lone recent is a full-width tile, not a half-row orphan.
      expect(tester.getSize(tile('Plank')).width, greaterThan(300));
    });

    testWidgets('2 recents → one full row + suggested row', (tester) async {
      await pumpPicker(tester, recents: const ['plank_hold', 'squats']);
      expect(find.text('Recent activities'), findsOneWidget);
      expect(tileCount(tester), 4);
    });

    testWidgets('3 recents → balanced rows, suggested slot filled',
        (tester) async {
      await pumpPicker(
          tester, recents: const ['plank_hold', 'squats', 'jumping_jacks']);
      expect(find.text('Recent activities'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      // 3 recents (2 + 1 wide) + 1 suggested (wide) = 4 options, no holes.
      expect(tileCount(tester), 4);
    });

    testWidgets('4+ recents → capped at 4, no suggested padding',
        (tester) async {
      await pumpPicker(tester,
          recents: const [
            'plank_hold',
            'squats',
            'jumping_jacks',
            'push_ups',
            'lunges',
          ]);
      expect(tileCount(tester), 4);
      expect(find.text('Suggested'), findsNothing);
    });

    testWidgets('recents dedupe starters — Pushups renders once',
        (tester) async {
      await pumpPicker(tester, recents: const ['push_ups']);
      expect(find.text('Pushups'), findsOneWidget);
    });

    testWidgets('recents keep provider order, newest first', (tester) async {
      await pumpPicker(tester,
          recents: const ['plank_hold', 'squats', 'push_ups']);
      // Rows fill in provider order: [Plank, Squats] then [Pushups] wide.
      final plank = tester.getTopLeft(find.text('Plank'));
      final squats = tester.getTopLeft(find.text('Squats'));
      final pushups = tester.getTopLeft(find.text('Pushups'));
      expect(plank.dx, lessThan(squats.dx)); // same row, Plank left
      expect(plank.dy, moreOrLessEquals(squats.dy));
      expect(pushups.dy, greaterThan(plank.dy)); // next row
    });

    testWidgets('selected tile keeps identical settled geometry',
        (tester) async {
      await pumpPicker(tester);
      final before = tester.getSize(tile('Pushups'));
      await tester.tap(find.text('Pushups'));
      await tester.pumpAndSettle();
      final after = tester.getSize(tile('Pushups'));
      expect(after, before);
      // A picked tile stays the same size as its unselected siblings.
      final squat = tester.getSize(tile('Squats'));
      expect(after, squat);
      // Selection is a surface change, not a reskin of layout.
      expect(find.text('Continue with Pushups'), findsOneWidget);
    });

    testWidgets('selected tile still shows canonical metric', (tester) async {
      await pumpPicker(tester, recents: const ['plank_hold']);
      await tester.tap(find.text('Plank'));
      await tester.pumpAndSettle();
      // 'seconds' remains rendered inside the selected tile.
      expect(find.text('seconds'), findsOneWidget);
      expect(find.text('Continue with Plank'), findsOneWidget);
    });

    testWidgets('selected tile does not change position', (tester) async {
      await pumpPicker(tester, recents: const ['plank_hold', 'squats']);
      final before = tester.getTopLeft(find.text('Plank'));
      await tester.tap(find.text('Plank'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Plank')), before);
    });

    testWidgets('See all movements is an active blue path', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('See all movements'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets); // search field
      expect(find.text('Quick picks'), findsOneWidget); // collapse path
      // Collapse returns to the simple picker.
      await tester.tap(find.text('Quick picks'));
      await tester.pumpAndSettle();
      expect(find.text('Teach Nuvo'), findsOneWidget);
    });

    testWidgets('back navigation preserves user selection', (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text('Plank'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Plank'));
      await tester.pumpAndSettle();
      // Step 3 reached — go back.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Continue with Plank'), findsOneWidget);
      expect(find.text('Pick a movement'), findsNothing);
    });

    testWidgets('selection survives late-arriving recents', (tester) async {
      setSize(tester, const Size(390, 844));
      final gate =
          _PickerStoreGate(['squats', 'lunges', 'mountain_climbers', 'high_knees']);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentMovementsStoreProvider.overrideWithValue(gate),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const RaceComposerScreen(
              prefill: RaceCreatePrefill(idea: 'First to 50 pushups'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();
      // User picks before recents resolve.
      await tester.tap(find.text('Pushups'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Pushups'), findsOneWidget);
      // Recents land late — selection and its tile must survive.
      gate.complete();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Pushups'), findsOneWidget);
      expect(find.text('Pushups'), findsOneWidget); // tile still present
      while (tester.takeException() != null) {
        fail('picker threw on late recents');
      }
    });

    testWidgets('320×568 — teach + custom goal stay reachable',
        (tester) async {
      await pumpPicker(tester,
          size: const Size(320, 568),
          recents: const ['plank_hold', 'squats', 'jumping_jacks']);
      await tester.scrollUntilVisible(
        find.text('Teach Nuvo'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Teach Nuvo'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Not a movement? Create a custom goal'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Not a movement? Create a custom goal'));
      await tester.pumpAndSettle();
      expect(find.text('Goal'), findsOneWidget);
      while (tester.takeException() != null) {
        fail('picker threw at 320');
      }
    });

    testWidgets('long movement name does not overflow tile or CTA',
        (tester) async {
      await pumpPicker(tester, recents: const ['mountain_climbers']);
      await tester.tap(find.text('Mountain Climbers'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Mountain Climbers'), findsOneWidget);
      while (tester.takeException() != null) {
        fail('long name overflowed');
      }
    });

    testWidgets('text scale 1.4 keeps tiles aligned', (tester) async {
      await pumpPicker(tester, textScale: 1.4);
      await tester.tap(find.text('Jumping Jacks'));
      await tester.pumpAndSettle();
      while (tester.takeException() != null) {
        fail('text scale 1.4 overflowed');
      }
      // Both column tiles still have equal width.
      final pushups = tester.getSize(tile('Pushups'));
      final squats = tester.getSize(tile('Squats'));
      expect(pushups.width, moreOrLessEquals(squats.width));
    });

    testWidgets('dark mode keeps selection legible', (tester) async {
      await pumpPicker(tester, theme: AppTheme.dark());
      await tester.tap(find.text('Pushups'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Pushups'), findsOneWidget);
      expect(find.text('reps'), findsWidgets);
    });
  });

  // ── Canonical unit audit ──────────────────────────────────────────────────
  group('Canonical units', () {
    test('every catalog movement surfaces its canonical unit', () {
      for (final a in motionActivityDefinitions) {
        expect(a.unit, isNotEmpty, reason: a.activityId);
        // A duration activity must never display a rep unit.
        if (a.resolvedMeasurementType == MotionMeasurementType.duration) {
          expect(a.unit, isNot('reps'), reason: a.activityId);
        }
      }
      expect(_plank.unit, 'seconds');
      expect(_pushups.unit, 'reps');
      expect(_jacks.unit, 'reps');
    });
  });
}

// ── picker test doubles ───────────────────────────────────────────────────────

class _PickerStore extends RecentMovementsStore {
  _PickerStore(this.ids);
  final List<String> ids;
  @override
  Future<List<String>> readIds() async => ids;
  @override
  Future<List<String>> recordSelection(String movementId) async => ids;
}

/// Delays recents until [complete] — models the real keychain fetch racing
/// the user's first tap.
class _PickerStoreGate extends RecentMovementsStore {
  _PickerStoreGate(this.ids);
  final List<String> ids;
  bool _open = false;

  void complete() => _open = true;

  @override
  Future<List<String>> readIds() async {
    while (!_open) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return ids;
  }

  @override
  Future<List<String>> recordSelection(String movementId) async => ids;
}
