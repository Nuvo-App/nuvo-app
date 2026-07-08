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
                label: 'Begin MoveCheck',
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

      // Race context — single clear header, no repetition
      Text(
        'VERIFY MOVE',
        style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
      ),
      const SizedBox(height: 4),
      Text(
        race.displayTitle,
        style: AppTextStyles.headlineMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      if (eligibility.isCameraVerifiable) ...[
        const SizedBox(height: 4),
        Text(
          'MoveCheck will count and verify automatically.',
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
        // Goal tile — standalone, not wrapped in a generic card
        Row(
          children: [
            Expanded(
              child: _MetricTile(label: 'Goal', value: _goalLabel),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Typical verification time',
                value: _estimatedTime,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Quick tips — actionable, movement-specific
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NuvoColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick tips',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in eligibility.instructions.take(3)) ...[
                _SetupLine(label: item),
                if (item != eligibility.instructions.take(3).last)
                  const SizedBox(height: 10),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Positioning preview
        Container(
          height: 178,
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NuvoColors.border),
          ),
          child: CustomPaint(
            painter: _MovePreviewPainter(
              sideView:
                  eligibility.preferredCameraView ==
                  PreferredCameraView.sideOrDiagonalRequired,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.navy),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
          ),
        ),
      ],
    );
  }
}

class _MovePreviewPainter extends CustomPainter {
  const _MovePreviewPainter({required this.sideView});

  final bool sideView;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = NuvoColors.blue.withValues(alpha: 0.32);
    canvas.drawRRect(frame, framePaint);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = NuvoColors.navy.withValues(alpha: 0.18);

    if (sideView) {
      // Plank / side silhouette — horizontal body
      final y = size.height * 0.54;
      final headR = size.width * 0.06;
      canvas.drawCircle(Offset(size.width * 0.18, y - 2), headR, fillPaint);

      final bodyRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(size.width * 0.26, y - 8, size.width * 0.82, y + 8),
        const Radius.circular(6),
      );
      canvas.drawRRect(bodyRect, fillPaint);

      // Supporting arms
      final armRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(size.width * 0.30, y + 6, size.width * 0.38, y + 28),
        const Radius.circular(3),
      );
      canvas.drawRRect(armRect, fillPaint);

      // Supporting legs
      final legRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(size.width * 0.72, y + 6, size.width * 0.80, y + 28),
        const Radius.circular(3),
      );
      canvas.drawRRect(legRect, fillPaint);
    } else {
      // Standing front silhouette — airport-icon style
      final cx = size.width * 0.5;
      final headR = size.width * 0.07;
      final headY = size.height * 0.22;
      canvas.drawCircle(Offset(cx, headY), headR, fillPaint);

      // Torso
      final torsoHW = size.width * 0.10;
      final torsoTop = headY + headR + size.height * 0.02;
      final torsoBottom = size.height * 0.58;
      final torsoRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - torsoHW, torsoTop, cx + torsoHW, torsoBottom),
        Radius.circular(torsoHW * 0.5),
      );
      canvas.drawRRect(torsoRect, fillPaint);

      // Arms
      final shoulderY = torsoTop + size.height * 0.03;
      final armW = size.width * 0.045;
      final armLen = size.height * 0.18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - torsoHW - armW, shoulderY, cx - torsoHW, shoulderY + armLen),
          Radius.circular(armW * 0.5),
        ),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx + torsoHW, shoulderY, cx + torsoHW + armW, shoulderY + armLen),
          Radius.circular(armW * 0.5),
        ),
        fillPaint,
      );

      // Legs
      final legW = size.width * 0.055;
      final legGap = size.width * 0.015;
      final legLen = size.height * 0.22;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - legGap - legW, torsoBottom, cx - legGap, torsoBottom + legLen),
          Radius.circular(legW * 0.4),
        ),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx + legGap, torsoBottom, cx + legGap + legW, torsoBottom + legLen),
          Radius.circular(legW * 0.4),
        ),
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MovePreviewPainter oldDelegate) =>
      oldDelegate.sideView != sideView;
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
