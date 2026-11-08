import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/friendly_error.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/data/auth_api.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/race_models.dart';
import '../../domain/camera_verification_resolver.dart';
import '../../domain/race_display.dart';
import '../../domain/race_mode_semantics.dart';
import '../ai_motion_proof_entry.dart';
import '../motion_catalog_provider.dart';
import '../race_controller.dart';

/// What the sheet hands back when a manual proof lands — the calling surface
/// (race card/detail) animates score, rank, and confetti from real values.
class SubmitProofOutcome {
  const SubmitProofOutcome({
    required this.value,
    this.result,
    required this.tookLead,
  });

  final int value;
  final RaceSubmissionResult? result;
  final bool tookLead;
}

/// The v13 proof chooser. Camera offers the existing AI Motion Proof route
/// (only when the movement is camera-verifiable); Manual logs an honor value
/// with the required photo evidence.
class SubmitProofV13Sheet extends ConsumerStatefulWidget {
  const SubmitProofV13Sheet({super.key, required this.race});

  final Race race;

  @override
  ConsumerState<SubmitProofV13Sheet> createState() =>
      _SubmitProofV13SheetState();
}

class _SubmitProofV13SheetState extends ConsumerState<SubmitProofV13Sheet> {
  int _tab = 0;
  int _value = 1;
  XFile? _evidence;
  bool _submitting = false;
  String? _error;

  CameraVerificationEligibility get _eligibility => resolveCameraVerification(
    widget.race,
    remoteDefinitions: availableMotionActivities(
      ref.read(motionCatalogProvider).valueOrNull,
      ref.read(motionCapabilitiesProvider),
    ),
  );

  int get _maxValue {
    if (widget.race.proofMode == 'manual') return 100000;
    return widget.race.metric == 'seconds' ? 28800 : 3000;
  }

  Future<void> _pickEvidence() async {
    final source = await showV13ActionSheet<ImageSource>(
      context,
      title: 'Proof photo',
      actions: const [
        V13SheetAction(
          label: 'Choose from photos',
          value: ImageSource.gallery,
          icon: Icons.photo_library_rounded,
        ),
        V13SheetAction(
          label: 'Take photo',
          value: ImageSource.camera,
          icon: Icons.photo_camera_rounded,
        ),
      ],
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked != null && mounted) setState(() => _evidence = picked);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = "Couldn't open your photos. Check access and try again.",
        );
      }
    }
  }

  String _evidenceContentType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
  }

  /// Client-side rank preview — same standing math the verifier context
  /// uses; the server still owns the final result.
  String _previewLine(int value) {
    final race = widget.race;
    final uid = ref.read(authControllerProvider).user?.id;
    final ctx = VerifierRaceContext.forRace(race, uid);
    final after = ctx.raceScoreAfter(value);
    final lower = race.scoreDirection == 'lower';
    var better = 0;
    var tying = 0;
    for (final p in race.participants) {
      if (p.userId == uid || p.progressValue <= 0) continue;
      final beats = lower ? p.progressValue < after : p.progressValue > after;
      if (beats) {
        better++;
      } else if (p.progressValue == after) {
        tying++;
      }
    }
    if (ctx.completesGoal(value)) return 'This crosses the finish line.';
    final projected = better + 1;
    if (projected == 1 && tying > 0) return 'This ties you for 1st.';
    if (projected == 1) return 'This moves you to 1st.';
    final current = rankForUser(race, uid);
    if (current != null && projected < current) {
      return 'This moves you to ${_ordinal(projected)}.';
    }
    if (current == null) {
      return 'This puts you on the board at ${_ordinal(projected)}.';
    }
    return 'Keeps you at ${_ordinal(current)}.';
  }

  static String _ordinal(int n) => switch (n) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };

  Future<void> _openCamera() async {
    // Same destination as the old chooser's Begin — the full verifier route.
    Navigator.of(context).pop();
    await openAiMotionProof(
      context,
      ref,
      widget.race,
      routeAction: 'v13_submit_proof_to_camera',
      fromPreview: true,
    );
  }

  Future<void> _submit() async {
    if (_value <= 0) {
      setState(() => _error = 'Enter how much you completed.');
      return;
    }
    if (_evidence == null) {
      setState(() => _error = 'Add a photo — proof is required for this race.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repo = ref.read(raceRepositoryProvider);
      final evidence = _evidence!;
      final contentType = _evidenceContentType(evidence.name);
      final urls = await repo.requestProofMediaUploadUrl(
        widget.race.id,
        fileName: evidence.name,
        contentType: contentType,
      );
      await repo.uploadProofMediaBytes(
        urls.uploadUrl,
        await evidence.readAsBytes(),
        contentType,
      );
      final updated = await ref
          .read(raceControllerProvider.notifier)
          .submitProof(
            widget.race.id,
            proofType: 'manual',
            value: _value,
            mediaObjectKey: urls.key,
          );
      if (!mounted) return;
      final result = updated.submissionResult;
      final uid = ref.read(authControllerProvider).user?.id;
      final tookLead =
          result != null &&
          (result.newRank == 1 && (result.previousRank ?? 99) > 1 ||
              result.winnerUserId == uid);
      Navigator.of(context).pop(
        SubmitProofOutcome(value: _value, result: result, tookLead: tookLead),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyApiError(e);
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not log your proof. Try again.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = _eligibility;
    final showCamera = eligibility.isCameraVerifiable;
    // Any movement Nuvo's camera can verify is camera-only in this app —
    // no Manual tab for AI-verified movements, whatever the race's rules
    // version (the Worker still accepts manual from older installed apps).
    // Manual stays only where the camera can't verify the movement.
    final cameraOnly = showCamera;
    final tab = !showCamera ? 1 : (cameraOnly ? 0 : _tab);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Submit proof', style: V13.sectionHead),
          const SizedBox(height: V13.gapMd),
          if (showCamera && !cameraOnly)
            V13Segmented(
              segments: const [
                V13Segment(label: 'Camera', icon: Icons.videocam_rounded),
                V13Segment(label: 'Manual', icon: Icons.edit_rounded),
              ],
              selectedIndex: tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          const SizedBox(height: V13.gapLg),
          if (tab == 0 && showCamera)
            _cameraPane(eligibility)
          else
            _manualPane(),
        ],
      ),
    );
  }

  Widget _cameraPane(CameraVerificationEligibility eligibility) {
    final instruction = eligibility.instructions.isNotEmpty
        ? eligibility.instructions.first
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const V13IconTile(icon: Icons.videocam_rounded, color: V13.sky),
            const SizedBox(width: V13.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Put your phone down so Nuvo sees your whole body.',
                    style: V13.body,
                  ),
                  if (instruction != null) ...[
                    const SizedBox(height: 4),
                    Text(instruction, style: V13.caption),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: V13.gapLg),
        V13Button.primary(
          label: 'Start camera proof',
          icon: Icons.videocam_rounded,
          onPressed: _submitting ? null : _openCamera,
        ),
      ],
    );
  }

  Widget _manualPane() {
    final unit = raceDisplayUnit(widget.race);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: V13Stepper(
            value: _value,
            min: 1,
            max: _maxValue,
            onChanged: (v) => setState(() => _value = v),
            semanticLabel: 'How many $unit',
          ),
        ),
        const SizedBox(height: 2),
        Center(child: Text(unit, style: V13.caption)),
        const SizedBox(height: V13.gapMd),
        Center(child: Text(_previewLine(_value), style: V13.bodyStrong)),
        const SizedBox(height: V13.gapMd),
        V13Pressable(
          onTap: _submitting ? null : _pickEvidence,
          pressDepth: 1.5,
          semanticLabel: _evidence == null
              ? 'Add a proof photo'
              : 'Change photo',
          child: Container(
            padding: const EdgeInsets.all(V13.gapMd),
            decoration: BoxDecoration(
              color: V13.bg,
              borderRadius: BorderRadius.circular(V13.radiusCard),
              border: Border.all(
                color: _error != null && _evidence == null
                    ? V13.danger
                    : V13.navy,
                width: V13.outline,
              ),
            ),
            child: Row(
              children: [
                V13IconTile(
                  icon: _evidence == null
                      ? Icons.add_a_photo_rounded
                      : Icons.check_circle_rounded,
                  color: _evidence == null ? V13.sun : V13.mint,
                ),
                const SizedBox(width: V13.gapMd),
                Expanded(
                  child: Text(
                    _evidence == null
                        ? 'Add a photo — proof is required'
                        : 'Photo added',
                    style: V13.bodyStrong,
                  ),
                ),
                if (_evidence != null)
                  V13Pressable(
                    onTap: () => setState(() => _evidence = null),
                    pressDepth: 1.5,
                    semanticLabel: 'Remove photo',
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: V13.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: V13.gapMd),
          Text(_error!, style: V13.caption.copyWith(color: V13.danger)),
        ],
        const SizedBox(height: V13.gapLg),
        V13Button.primary(
          label: 'Log proof',
          icon: Icons.check_rounded,
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
