import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import '../domain/motion_activity.dart';
import 'race_controller.dart';

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
      setState(() {
        _race = race;
        _raceLoading = false;
      });
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      bottomNavigationBar: _bottomBar(race),
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                ),
      ),
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────────────

  Widget? _bottomBar(Race? race) {
    if (_raceLoading || _raceError != null) return null;

    final r = race;
    if (r == null) return null;
    final eligibility = resolveCameraVerification(r);

    if (eligibility.isCameraVerifiable) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NuvoPrimaryButton(
                label: 'Begin',
                icon: Icons.camera_alt_rounded,
                expand: true,
                onPressed: () {
                  debugLogCameraVerificationDecision(
                    r,
                    eligibility,
                    routeAction: 'submit_proof_to_camera',
                  );
                  context.push('/race/${widget.raceId}/proof/ai-motion');
                },
              ),
              const SizedBox(height: 10),
              NuvoGhostButton(
                label: 'Back to race',
                expand: true,
                onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: NuvoGhostButton(
          label: 'View race',
          expand: true,
          onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
        ),
      ),
    );
  }

  // ── Loading ──────────────────────────────────────────────────────────────────

  List<Widget> _loadingContent() => [
    _backRow(),
    const SizedBox(height: 100),
    const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
    return [
      _backRow(),
      const SizedBox(height: 24),

      Text(
        race.displayTitle,
        style: AppTextStyles.headlineMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      if (eligibility.isCameraVerifiable) ...[
        const SizedBox(height: 4),
        Text(
          'Camera counts and verifies automatically.',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
      ] else ...[
        const SizedBox(height: 4),
        Text(
          eligibility.unsupportedMessage,
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
      ],

      const SizedBox(height: 24),

      if (eligibility.isCameraVerifiable)
        _MoveCheckCard(race: race, eligibility: eligibility)
      else
        _UnsupportedVerificationCard(message: eligibility.unsupportedMessage),
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
    final activity = eligibility.movementDefinition;
    if (race.targetValue != null && activity != null) {
      return activity.targetLabel(race.targetValue!);
    }
    if (activity != null) {
      return activity.targetLabel(activity.defaultTarget);
    }
    return race.targetValue?.toString() ?? 'Ready';
  }

  IconData get _movementIcon => switch (eligibility.movementType) {
    MotionActivityType.pushUps => Icons.front_hand_rounded,
    MotionActivityType.plankHold => Icons.straighten_rounded,
    MotionActivityType.jumpingJacks => Icons.accessibility_new_rounded,
    MotionActivityType.squats => Icons.person_outline_rounded,
    MotionActivityType.lunges => Icons.directions_walk_rounded,
    _ => Icons.person_outline_rounded,
  };

  String get _framingLabel => switch (eligibility.movementType) {
    MotionActivityType.pushUps => 'Upper body + hands visible',
    MotionActivityType.plankHold => 'Side view · full body in frame',
    MotionActivityType.jumpingJacks => 'Full body · leave room for arms',
    MotionActivityType.squats => 'Full body centered in frame',
    MotionActivityType.lunges => 'Full body · lower body visible',
    _ => 'Full body inside frame',
  };

  String get _estimatedTime {
    final activity = eligibility.movementDefinition;
    final target = race.targetValue ?? activity?.defaultTarget ?? 10;
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

        // Framing illustration — just corner brackets + instruction text
        // This is what professional apps do: show framing, not a person
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


class _UnsupportedVerificationCard extends StatelessWidget {
  const _UnsupportedVerificationCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.videocam_off_rounded,
              color: NuvoColors.navy,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}
