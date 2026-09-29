import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_fade_scroll.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/data/first_use_store.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/race_display.dart';
import '../domain/motion_activity.dart';
import 'board_moved_screen.dart';
import 'motion_catalog_provider.dart';
import 'race_controller.dart';
import 'widgets/rive_movement_preview.dart';

class SubmitProofScreen extends ConsumerStatefulWidget {
  const SubmitProofScreen({super.key, required this.raceId});
  final String raceId;

  @override
  ConsumerState<SubmitProofScreen> createState() => _SubmitProofScreenState();
}

class _SubmitProofScreenState extends ConsumerState<SubmitProofScreen> {
  Race? _race;
  bool _raceLoading = true;
  String? _raceError;
  bool _navigating = false;

  // Manual / non-camera goal logging.
  final _logController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submittingManual = false;
  String? _manualError;
  XFile? _evidence;

  /// Control-plane definitions for resolving remote-only race activities
  /// (motions this build has no compiled enum for). Falls back to bundled
  /// definitions when the catalog has not loaded yet.
  List<MotionActivityDefinition> get _remoteDefinitions =>
      availableMotionActivities(
        ref.read(motionCatalogProvider).valueOrNull,
        ref.read(motionCapabilitiesProvider),
      );

  @override
  void dispose() {
    _logController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitManual(Race race) async {
    // A manual-goal race has no Begin button — the real submit is the guide's
    // last action instead.
    if (ref.read(firstRaceGuideProvider) == FirstRaceGuideStep.verifySetup) {
      completeFirstRaceGuide(ref);
    }
    final value = int.tryParse(_logController.text.trim());
    if (value == null || value <= 0) {
      setState(() => _manualError = 'Enter how much you completed.');
      return;
    }
    // Evidence contract — self-reported results require a photo. The server
    // enforces the same rule; this check just fails before the upload.
    if (_evidence == null) {
      setState(
        () => _manualError = 'Add a photo — proof is required for this race.',
      );
      return;
    }
    setState(() {
      _submittingManual = true;
      _manualError = null;
    });
    HapticFeedback.mediumImpact();
    try {
      // Evidence first: upload through the race-scoped signed URL so the
      // submit can bind the object key — the proof POST stays unchanged
      // otherwise.
      String? mediaObjectKey;
      final evidence = _evidence;
      if (evidence != null) {
        final repo = ref.read(raceRepositoryProvider);
        final contentType = _evidenceContentType(evidence.name);
        final urls = await repo.requestProofMediaUploadUrl(
          widget.raceId,
          fileName: evidence.name,
          contentType: contentType,
        );
        await repo.uploadProofMediaBytes(
          urls.uploadUrl,
          await evidence.readAsBytes(),
          contentType,
        );
        mediaObjectKey = urls.key;
      }
      final note = _noteController.text.trim();
      final updated = await ref
          .read(raceControllerProvider.notifier)
          .submitProof(
            widget.raceId,
            proofType: 'manual',
            note: note.isEmpty ? null : note,
            value: value,
            mediaObjectKey: mediaObjectKey,
          );
      if (!mounted) return;
      final proof = updated.recentProofs.isNotEmpty
          ? updated.recentProofs.first
          : null;
      context.pushReplacement(
        '/race/${widget.raceId}/board-moved',
        extra: BoardMovedArgs(
          raceId: widget.raceId,
          raceName: updated.displayTitle,
          value: value,
          unit: updated.unit,
          status: proof?.verificationStatus ?? 'accepted',
          rankBefore: proof?.rankBefore,
          rankAfter: proof?.rankAfter ?? rankForUser(updated, _uid),
          peoplePassed: proof?.peoplePassed,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _manualError = e.message;
          _submittingManual = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _manualError = 'Could not log your progress. Try again.';
          _submittingManual = false;
        });
      }
    }
  }

  String? get _uid => ref.read(authControllerProvider).user?.id;

  String _evidenceContentType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
  }

  Future<void> _pickEvidence() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.themeColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text('Proof photo', style: AppTextStyles.titleLarge),
              const SizedBox(height: 16),
              _EvidenceSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from photos',
                onTap: () =>
                    Navigator.of(sheetCtx).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
              _EvidenceSheetOption(
                icon: Icons.photo_camera_rounded,
                label: 'Take photo',
                onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _evidence = picked);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRace();
  }

  Future<void> _loadRace() async {
    setState(() {
      _raceLoading = true;
      _raceError = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      if (!mounted) return;
      final eligibility = resolveCameraVerification(race, remoteDefinitions: _remoteDefinitions);
      setState(() {
        _race = race;
        _raceLoading = false;
      });
      debugLogCameraVerificationDecision(
        race,
        eligibility,
        routeAction: 'submit_proof_entry_loaded',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _raceError = 'Could not load race details.';
        _raceLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = _race;
    final isPreVerify =
        !_raceLoading &&
        _raceError == null &&
        race != null &&
        _isPreVerify(race);

    final screen = Scaffold(
      backgroundColor: context.themeColors.page,
      bottomNavigationBar: _bottomBar(race),
      body: SafeArea(
        child: isPreVerify ? _centeredPreVerifyBody(race) : _defaultBody(race),
      ),
    );

    // Final coach step: the real Begin button on the pre-verify setup.
    // Only while that button actually exists (camera-verifiable race, loaded).
    if (ref.watch(firstRaceGuideProvider) == FirstRaceGuideStep.verifySetup &&
        isPreVerify) {
      return Stack(
        children: [
          screen,
          FirstRaceGuideCoach(
            step: FirstRaceGuideStep.verifySetup,
            targetKey: FirstRaceGuideKeys.verifyBegin,
            eyebrow: 'READY TO MOVE',
            title: 'Get in position.',
            body: 'Tap Begin when you’re ready.',
          ),
        ],
      );
    }
    return screen;
  }

  bool _isPreVerify(Race race) {
    final eligibility = resolveCameraVerification(race, remoteDefinitions: _remoteDefinitions);
    return eligibility.isCameraVerifiable && eligibility.movementType != null;
  }

  Widget _defaultBody(Race? race) {
    return NuvoFadeScroll(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
        children: _raceLoading
            ? _loadingContent()
            : _raceError != null
            ? _errorContent()
            : _formContent(race!),
      ),
    );
  }

  Widget _centeredPreVerifyBody(Race race) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: _backRow()),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: _preVerifyContent(race),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────────────

  /// Always returns a bar so the page does not reflow when the race finishes
  /// loading. While loading, the primary action is shown in its disabled
  /// loading state instead of appearing suddenly underneath the content.
  Widget _bottomBar(Race? race) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _bottomBarActions(race),
        ),
      ),
    );
  }

  List<Widget> _bottomBarActions(Race? race) {
    final backToRace = NuvoTertiaryButton(
      label: 'Back to race',
      expand: true,
      onPressed: _leave,
    );

    if (_raceLoading) {
      // Mirrors the camera layout (the common case) so the bar keeps its height.
      return [
        const NuvoPrimaryButton(
          label: 'Begin',
          icon: Icons.camera_alt_rounded,
          expand: true,
          loading: true,
        ),
        const SizedBox(height: 10),
        backToRace,
      ];
    }

    if (_raceError != null || race == null) return [backToRace];

    final eligibility = resolveCameraVerification(race, remoteDefinitions: _remoteDefinitions);
    if (!eligibility.isCameraVerifiable) {
      return [
        NuvoPrimaryButton(
          label: 'Log progress',
          icon: Icons.check_rounded,
          expand: true,
          loading: _submittingManual,
          onPressed: _submittingManual ? null : () => _submitManual(race),
        ),
        const SizedBox(height: 10),
        backToRace,
      ];
    }

    return [
      NuvoPrimaryButton(
        key: FirstRaceGuideKeys.verifyBegin,
        label: 'Begin',
        icon: Icons.camera_alt_rounded,
        expand: true,
        onPressed: _navigating
            ? null
            : () => _beginCameraProof(race, eligibility),
      ),
      const SizedBox(height: 10),
      backToRace,
    ];
  }

  Future<void> _beginCameraProof(
    Race race,
    CameraVerificationEligibility eligibility,
  ) async {
    if (_navigating) return;
    // Begin is the guide's final coached action — the camera flow teaches
    // itself from here.
    if (ref.read(firstRaceGuideProvider) == FirstRaceGuideStep.verifySetup) {
      completeFirstRaceGuide(ref);
    }
    // First camera use gets the why-before-the-ask primer — the OS prompt
    // itself is what the camera plugin raises inside the proof flow. Shown
    // once per install; a dismissed primer asks again next time.
    final firstUse = ref.read(firstUseStoreProvider);
    if (!firstUse.isCameraPrimerSeen) {
      final proceed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.themeColors.page,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const _CameraPrimerSheet(),
      );
      if (proceed != true) return;
      await firstUse.markCameraPrimerSeen();
    }
    if (!mounted) return;
    setState(() => _navigating = true);
    HapticFeedback.mediumImpact();
    debugLogCameraVerificationDecision(
      race,
      eligibility,
      routeAction: 'submit_proof_to_camera',
    );
    try {
      await context.push('/race/${widget.raceId}/proof/ai-motion');
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _leave() async {
    if (!_submittingManual && !_navigating) {
      safePopOrGo(context, '/race/${widget.raceId}');
      return;
    }
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: 'Leave proof submission?',
      message: 'Your current proof will not be submitted.',
      cancelLabel: 'Keep recording',
      confirmLabel: 'Leave',
      destructive: false,
    );
    if (confirmed == true && mounted) {
      safePopOrGo(context, '/race/${widget.raceId}');
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────────

  /// Mirrors the shape of the loaded layout so nothing shifts on arrival.
  List<Widget> _loadingContent() => [
    _backRow(),
    const SizedBox(height: 24),
    const _SkeletonBlock(width: 190, height: 34),
    const SizedBox(height: 12),
    const _SkeletonBlock(width: 240, height: 18),
    const SizedBox(height: 8),
    const _SkeletonBlock(width: 160, height: 13),
    const SizedBox(height: 32),
    const _SkeletonBlock(width: 130, height: 16),
    const SizedBox(height: 20),
    const _SkeletonBlock(height: 160, radius: 20),
    const SizedBox(height: 20),
    const _SkeletonBlock(width: 220, height: 14),
    const SizedBox(height: 10),
    const _SkeletonBlock(width: 190, height: 14),
  ];

  // ── Error ────────────────────────────────────────────────────────────────────

  List<Widget> _errorContent() => [
    _backRow(),
    const SizedBox(height: 60),
    NuvoErrorState(message: _raceError!, onRetry: _loadRace),
  ];

  // ── Form ─────────────────────────────────────────────────────────────────────

  List<Widget> _formContent(Race race) {
    final eligibility = resolveCameraVerification(race, remoteDefinitions: _remoteDefinitions);

    // Keep every camera-verifiable movement on the same quiet setup screen.
    if (_isPreVerify(race)) {
      return _preVerifyContent(race);
    }

    return [
      _backRow(),
      const SizedBox(height: 24),

      Text(
        eligibility.isCameraVerifiable ? 'Submit proof' : 'Log progress',
        style: AppTextStyles.headlineLarge.copyWith(
          fontSize: 32,
          letterSpacing: -0.9,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        race.displayTitle,
        style: AppTextStyles.titleMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        eligibility.isCameraVerifiable
            ? 'Camera counts and verifies automatically.'
            : 'Log your result — a photo proves it counts.',
        style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
      ),

      const SizedBox(height: 24),

      if (eligibility.isCameraVerifiable)
        _MoveCheckCard(race: race, eligibility: eligibility)
      else
        _ManualLogCard(
          race: race,
          startingProgress: _uid == null
              ? 0
              : race.participantFor(_uid!)?.progressValue ?? 0,
          valueController: _logController,
          noteController: _noteController,
          error: _manualError,
          evidence: _evidence,
          onPickEvidence: _pickEvidence,
          onClearEvidence: () => setState(() => _evidence = null),
        ),
    ];
  }

  /// Dedicated pre-verification movement instruction shown before the camera opens.
  List<Widget> _preVerifyContent(Race race) {
    final eligibility = resolveCameraVerification(race, remoteDefinitions: _remoteDefinitions);
    final movementName =
        eligibility.movementDefinition?.title ?? race.displayTitle;
    final framingLabel =
        eligibility.movementDefinition?.framingLabel ??
        'Full body inside frame';
    final goalLabel = race.targetValue != null ? raceTargetLabel(race) : null;
    return [
      Text(
        movementName,
        style: AppTextStyles.headlineLarge.copyWith(
          fontSize: 32,
          letterSpacing: -0.9,
        ),
        textAlign: TextAlign.center,
      ),
      if (goalLabel != null) ...[
        const SizedBox(height: 6),
        Text(
          'First to $goalLabel',
          style: AppTextStyles.titleMedium.copyWith(color: context.themeColors.inkMuted),
          textAlign: TextAlign.center,
        ),
      ],

      const SizedBox(height: 32),

      _PreVerifySetupCard(movementType: eligibility.movementType),
      const SizedBox(height: 24),

      // Camera/setup instruction
      Text(
        framingLabel,
        style: AppTextStyles.bodyLarge.copyWith(
          color: context.themeColors.ink,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 6),
      Text(
        'Stand where Nuvo can see your whole body.',
        style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
        textAlign: TextAlign.center,
      ),
    ];
  }

  Widget _backRow() => NuvoBackButton(onPressed: _leave);
}

// ── MoveCheck card ────────────────────────────────────────────────────────────

class _MoveCheckCard extends StatelessWidget {
  const _MoveCheckCard({required this.race, required this.eligibility});
  final Race race;
  final CameraVerificationEligibility eligibility;

  String get _goalLabel {
    if (race.targetValue != null) return raceTargetLabel(race);
    return 'Ready';
  }

  IconData get _movementIcon =>
      eligibility.movementDefinition?.icon ?? Icons.person_outline_rounded;

  String get _framingLabel =>
      eligibility.movementDefinition?.framingLabel ?? 'Full body inside frame';

  String get _estimatedTime {
    final activity = eligibility.movementDefinition;
    final target = race.targetValue ?? activity?.defaultTarget ?? 1;
    if (activity?.isHold == true) {
      return '~${target + 5} sec';
    }
    // Realistic estimate: ~3 sec per rep for most movements
    final seconds = (target * 3).clamp(15, 300);
    if (seconds >= 60) {
      final min = seconds ~/ 60;
      final sec = seconds % 60;
      return sec > 0 ? '~$min min $sec sec' : '~$min min';
    }
    return '~$seconds sec';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Goal — simple inline row
        Row(
          children: [
            Text(
              'Goal',
              style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
            ),
            const SizedBox(width: 12),
            Text(
              _goalLabel,
              style: AppTextStyles.titleMedium.copyWith(color: context.themeColors.ink),
            ),
            const Spacer(),
            Text(
              _estimatedTime,
              style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Framing illustration — corner brackets + instruction text
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(
            painter: _FramingGuidePainter(
              color: context.themeColors.ink,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _movementIcon,
                    color: context.themeColors.ink.withValues(alpha: 0.18),
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _framingLabel,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: context.themeColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Tips — no card, just clean text lines
        for (final item in eligibility.instructions.take(3)) ...[
          _SetupLine(label: item),
          if (item != eligibility.instructions.take(3).last)
            const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Pre-verification movement cue. The camera screen remains the source of
/// truth for live verification; this surface is decorative guidance only.
class _PreVerifySetupCard extends ConsumerWidget {
  const _PreVerifySetupCard({this.movementType});

  final MotionActivityType? movementType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movement = movementType;
    // Decorative-only lookup: an unloaded/errored catalog just means no
    // remote preview override, never a verification-affecting failure.
    final remotePreviewJson = movement == null
        ? null
        : ref
            .watch(motionCatalogProvider)
            .whenOrNull(
              data: (snapshot) => snapshot.previewSequenceFor(
                movement.backendValue,
              ),
            );
    final showRivePreview =
        movement != null &&
        RiveMovementPreview.supports(
          movement,
          remotePreviewJson: remotePreviewJson,
        );
    return Semantics(
      label: 'Camera verification is ready. Tap Begin to open the camera.',
      child: Container(
        width: double.infinity,
        padding: showRivePreview
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: showRivePreview
            ? const BoxDecoration(color: Colors.transparent)
            : BoxDecoration(
                color: context.semanticColors.neutral.surface,
                borderRadius: BorderRadius.circular(NuvoRadii.card),
                border: Border.all(color: context.themeColors.border, width: 2),
              ),
        child: SizedBox(
          height: showRivePreview ? 300 : 78,
          child: showRivePreview
              ? RiveMovementPreview(
                  movement: movement,
                  fallback: const _StaticPreVerifyCue(),
                  remotePreviewJson: remotePreviewJson,
                )
              : const _StaticPreVerifyCue(),
        ),
      ),
    );
  }
}

class _StaticPreVerifyCue extends StatelessWidget {
  const _StaticPreVerifyCue();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          const Icon(Icons.videocam_outlined, color: NuvoColors.blue, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Camera opens after Begin',
              style: AppTextStyles.titleMedium.copyWith(
                color: context.themeColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramingGuidePainter extends CustomPainter {
  const _FramingGuidePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 28.0;
    const inset = 24.0;

    // Top-left
    canvas.drawLine(
      const Offset(inset, inset + corner),
      const Offset(inset, inset),
      paint,
    );
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset + corner, inset),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(size.width - inset - corner, inset),
      Offset(size.width - inset, inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + corner),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(inset, size.height - inset - corner),
      Offset(inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + corner, size.height - inset),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - inset - corner, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset - corner),
      Offset(size.width - inset, size.height - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.themeColors.divider.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SetupLine extends StatelessWidget {
  const _SetupLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: NuvoColors.blue,
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(color: context.themeColors.ink),
          ),
        ),
      ],
    );
  }
}

/// Manual progress entry for non-camera goals (manual / honor / check-in).
class _ManualLogCard extends StatelessWidget {
  const _ManualLogCard({
    required this.race,
    required this.startingProgress,
    required this.valueController,
    required this.noteController,
    required this.error,
    required this.evidence,
    required this.onPickEvidence,
    required this.onClearEvidence,
  });

  final Race race;

  /// Progress already banked on this race — the entry continues from here.
  final int startingProgress;
  final TextEditingController valueController;
  final TextEditingController noteController;
  final String? error;
  final XFile? evidence;
  final VoidCallback onPickEvidence;
  final VoidCallback onClearEvidence;

  @override
  Widget build(BuildContext context) {
    final unit = race.unit?.trim().isNotEmpty == true ? race.unit! : 'done';
    // Attempt races track a best score, not progress toward a finish line —
    // the stored target is a scale hint, not a goal to chase.
    final isAttempt = raceFormatUsesAttempts(race.format);
    final target = isAttempt ? null : race.targetValue;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.themeColors.border, width: 2),
        boxShadow: AppShadows.hardSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                startingProgress > 0 ? 'Your progress' : 'Finish line',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.themeColors.inkMuted,
                ),
              ),
              const Spacer(),
              Text(
                target != null
                    ? (startingProgress > 0
                          ? '$startingProgress / $target $unit'
                          : '$target $unit')
                    : (startingProgress > 0
                          ? '$startingProgress $unit'
                          : 'No set target'),
                style: AppTextStyles.titleMedium.copyWith(
                  color: context.themeColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NuvoTextInput(
            controller: valueController,
            label: startingProgress > 0
                ? 'How much did you add this time? ($unit)'
                : 'How much did you complete? ($unit)',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          NuvoTextInput(
            controller: noteController,
            label: 'Add a note (optional)',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          _EvidenceTile(
            evidence: evidence,
            onPick: onPickEvidence,
            onClear: onClearEvidence,
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Evidence tile ─────────────────────────────────────────────────────────────

/// One row inside the manual card: empty state is a quiet "Add photo"
/// affordance; once picked it swaps to a thumbnail + remove. Generic — the
/// label comes from the race's proof language, not a subject-specific screen.
class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.evidence,
    required this.onPick,
    required this.onClear,
  });

  final XFile? evidence;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final picked = evidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proof',
          style: AppTextStyles.bodySmall.copyWith(color: context.themeColors.inkMuted),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.semanticColors.neutral.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.themeColors.border, width: 1.5),
            ),
            child: picked == null
                ? Row(
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 20,
                        color: context.themeColors.ink,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Add photo',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: context.themeColors.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'required',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.danger,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(picked.path),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Photo added',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: context.themeColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: context.themeColors.inkMuted,
                        onPressed: onClear,
                        tooltip: 'Remove photo',
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Mirror of the sheet-option row used by the profile photo sheet — same
/// visual language, scoped privately here.
class _EvidenceSheetOption extends StatelessWidget {
  const _EvidenceSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.semanticColors.neutral.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.themeColors.ink),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.titleMedium),
          ],
        ),
      ),
    );
  }
}

// ── Camera primer ────────────────────────────────────────────────────────────

/// One-time "why the camera" sheet shown before the first AI Motion launch.
/// Education only — the OS permission dialog belongs to the camera plugin
/// inside the proof flow; this sheet never triggers it.
class _CameraPrimerSheet extends StatelessWidget {
  const _CameraPrimerSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.panel,
                  border: Border.all(color: c.ink, width: 1.6),
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  color: NuvoColors.blue,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Move. We’ll verify it.',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(
                color: c.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nuvo uses your camera to track your movement while you race.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: c.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (i, fact) in const [
                  (
                    icon: Icons.accessibility_new_rounded,
                    label: 'Processed for motion',
                  ),
                  (
                    icon: Icons.videocam_off_rounded,
                    label: 'Video isn’t uploaded',
                  ),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Icon(fact.icon, color: NuvoColors.blue, size: 22),
                        const SizedBox(height: 6),
                        Text(
                          fact.label,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            NuvoPrimaryButton(
              label: 'Continue',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: AppTextStyles.titleMedium.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
