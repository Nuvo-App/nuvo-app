import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/race_display.dart';
import 'board_moved_screen.dart';
import 'race_controller.dart';
import 'widgets/preset_movement_demos.dart';

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

  @override
  void dispose() {
    _logController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitManual(Race race) async {
    final value = int.tryParse(_logController.text.trim());
    if (value == null || value <= 0) {
      setState(() => _manualError = 'Enter how much you completed.');
      return;
    }
    setState(() {
      _submittingManual = true;
      _manualError = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final note = _noteController.text.trim();
      final updated = await ref
          .read(raceControllerProvider.notifier)
          .submitProof(
            widget.raceId,
            proofType: 'manual',
            note: note.isEmpty ? null : note,
            value: value,
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
      final eligibility = resolveCameraVerification(race);
      // Show a pre-verify movement demo before the camera opens when a
      // demo is available for the movement. Other camera-verifiable presets
      // skip straight to the AI Motion screen.
      final hasPreVerifyDemo =
          eligibility.isCameraVerifiable &&
          eligibility.movementType != null &&
          movementDemoForType(eligibility.movementType!) != null;
      if (eligibility.isCameraVerifiable && !hasPreVerifyDemo && mounted) {
        context.push('/race/${widget.raceId}/proof/ai-motion');
        return;
      }
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
    final isPreVerify = !_raceLoading &&
        _raceError == null &&
        race != null &&
        _isPreVerify(race);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: _bottomBar(race),
      body: SafeArea(
        child: isPreVerify
            ? _centeredPreVerifyBody(race)
            : _defaultBody(race),
      ),
    );
  }

  bool _isPreVerify(Race race) {
    final eligibility = resolveCameraVerification(race);
    return eligibility.isCameraVerifiable &&
        eligibility.movementType != null &&
        movementDemoForType(eligibility.movementType!) != null;
  }

  Widget _defaultBody(Race? race) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: _raceLoading
          ? _loadingContent()
          : _raceError != null
              ? _errorContent()
              : _formContent(race!),
    )
        .animate()
        .fadeIn(duration: 240.ms, curve: Curves.easeOut)
        .slideY(
          begin: 0.03,
          end: 0,
          duration: 280.ms,
          curve: Curves.easeOutCubic,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _preVerifyContent(race),
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
      onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
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

    final eligibility = resolveCameraVerification(race);
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
    final eligibility = resolveCameraVerification(race);

    // Show pre-verify movement demo when a demo is available.
    if (eligibility.isCameraVerifiable &&
        eligibility.movementType != null &&
        movementDemoForType(eligibility.movementType!) != null) {
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
            : 'Add how much you completed toward the finish line.',
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
      ),

      const SizedBox(height: 24),

      if (eligibility.isCameraVerifiable)
        _MoveCheckCard(race: race, eligibility: eligibility)
      else
        _ManualLogCard(
          race: race,
          startingProgress:
              _uid == null ? 0 : race.participantFor(_uid!)?.progressValue ?? 0,
          valueController: _logController,
          noteController: _noteController,
          error: _manualError,
        ),
    ];
  }

  /// Dedicated pre-verification movement instruction shown before the camera opens.
  List<Widget> _preVerifyContent(Race race) {
    final eligibility = resolveCameraVerification(race);
    final movementName =
        eligibility.movementDefinition?.title ?? race.displayTitle;
    final framingLabel =
        eligibility.movementDefinition?.framingLabel ??
        'Full body inside frame';
    final goalLabel = race.targetValue != null ? raceTargetLabel(race) : null;

    return [
      // Movement name — large, clear
      Text(
        movementName,
        style: AppTextStyles.headlineLarge.copyWith(
          fontSize: 32,
          letterSpacing: -0.9,
        ),
        textAlign: TextAlign.center,
      ).animate().fadeIn(duration: 220.ms),
      if (goalLabel != null) ...[
        const SizedBox(height: 6),
        Text(
          'First to $goalLabel',
          style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.muted),
          textAlign: TextAlign.center,
        ).animate(delay: 60.ms).fadeIn(duration: 220.ms),
      ],

      const SizedBox(height: 32),

      // Camera/setup instruction
      Text(
        framingLabel,
        style: AppTextStyles.bodyLarge.copyWith(
          color: NuvoColors.navy,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ).animate(delay: 120.ms).fadeIn(duration: 220.ms),
      const SizedBox(height: 6),
      Text(
        'Stand where Nuvo can see your whole body.',
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        textAlign: TextAlign.center,
      ).animate(delay: 160.ms).fadeIn(duration: 220.ms),
    ];
  }

  Widget _backRow() => NuvoBackButton(
    onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
  );
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
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(width: 12),
            Text(
              _goalLabel,
              style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.navy),
            ),
            const Spacer(),
            Text(
              _estimatedTime,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Framing illustration — corner brackets + instruction text
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(
            painter: _FramingGuidePainter(),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _movementIcon,
                    color: NuvoColors.navy.withValues(alpha: 0.18),
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _framingLabel,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.muted,
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

class _FramingGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NuvoColors.navy.withValues(alpha: 0.14)
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
            color: NuvoColors.divider.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 620.ms, begin: 0.45, curve: Curves.easeInOut);
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
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
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
  });

  final Race race;

  /// Progress already banked on this race — the entry continues from here.
  final int startingProgress;
  final TextEditingController valueController;
  final TextEditingController noteController;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final unit = race.unit?.trim().isNotEmpty == true ? race.unit! : 'done';
    final target = race.targetValue;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.navy, width: 2),
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
                  color: NuvoColors.muted,
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
                  color: NuvoColors.navy,
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
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
