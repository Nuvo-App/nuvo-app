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
                label: 'Check with MoveCheck',
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
                label: 'View race',
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

      // Race context
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
      const SizedBox(height: 4),
      Text(
        _raceSubtitle(race),
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
      ),

      const SizedBox(height: 28),

      if (eligibility.isCameraVerifiable)
        _MoveCheckCard(race: race, eligibility: eligibility)
      else
        _UnsupportedVerificationCard(message: eligibility.unsupportedMessage),
    ];
  }

  Widget _backRow() => NuvoBackButton(
    onPressed: () => safePopOrGo(context, '/race/${widget.raceId}'),
  );

  String _raceSubtitle(Race race) {
    final eligibility = resolveCameraVerification(race);
    if (eligibility.isCameraVerifiable) {
      final activity = eligibility.movementDefinition;
      if (race.targetValue != null && activity != null) {
        return 'MoveCheck · First to ${activity.targetLabel(race.targetValue!)}';
      }
      return 'MoveCheck';
    }
    return eligibility.unsupportedMessage;
  }
}

// ── MoveCheck card ────────────────────────────────────────────────────────────

class _MoveCheckCard extends StatelessWidget {
  const _MoveCheckCard({required this.race, required this.eligibility});
  final Race race;
  final CameraVerificationEligibility eligibility;

  String _description() {
    final activity = eligibility.movementDefinition;
    if (race.targetValue != null && activity != null) {
      return 'Nuvo will count your ${activity.targetLabel(race.targetValue!)} through the camera.';
    }
    if (activity != null) {
      return 'Nuvo will verify your ${activity.unit} through the camera.';
    }
    return 'Nuvo can’t verify this movement yet.';
  }

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
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.camera_alt_rounded,
              color: NuvoColors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MoveCheck', style: AppTextStyles.titleLarge),
                const SizedBox(height: 4),
                Text(
                  _description(),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
