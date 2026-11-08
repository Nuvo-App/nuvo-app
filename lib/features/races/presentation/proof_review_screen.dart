import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/network/api_base.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/v13/v13.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../data/race_models.dart';
import '../domain/race_display.dart';
import 'race_controller.dart';
import 'v13/submit_proof_entry.dart';

/// `/race/:id/proofs/:proofId` — inspect one proof. The race creator gets
/// accept / ask-for-another / reject controls on held proof; other racers
/// see the verdict and can veto or report. All writes keep their existing
/// controller calls — only the chrome changed.
class ProofReviewScreen extends ConsumerStatefulWidget {
  const ProofReviewScreen({
    super.key,
    required this.raceId,
    required this.proofId,
  });

  final String raceId;
  final String proofId;

  @override
  ConsumerState<ProofReviewScreen> createState() => _ProofReviewScreenState();
}

class _ProofReviewScreenState extends ConsumerState<ProofReviewScreen> {
  final _summaryController = TextEditingController();
  Race? _race;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _accessToken;

  RaceProof? get _proof {
    final race = _race;
    if (race == null) return null;
    for (final proof in race.recentProofs) {
      if (proof.id == widget.proofId) return proof;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      // Evidence media is participant-gated — fetched with the Bearer header,
      // not as a public URL.
      final token = await ref.read(secureTokenStoreProvider).getAccessToken();
      if (mounted) {
        setState(() {
          _race = race;
          _accessToken = token;
          _summaryController.text = _proof?.verificationSummary ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load move review.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(String status) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final summary = _summaryController.text.trim();
      final race = await ref
          .read(raceControllerProvider.notifier)
          .reviewProof(
            widget.raceId,
            widget.proofId,
            status: status,
            summary: summary.isEmpty ? null : summary,
          );
      if (mounted) {
        final message = switch (status) {
          'accepted' => 'Proof accepted.',
          'rejected' => 'Proof rejected.',
          _ => 'Asked for another proof.',
        };
        showV13Toast(context, message);
        context.go('/race/${race.id}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyApiError(e);
          _saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not review move.';
          _saving = false;
        });
      }
    }
  }

  /// Veto reasons mirror the server's VETO_REASONS — a veto disputes whether
  /// this proof should count in THIS race (distinct from Report, which goes
  /// to the Nuvo team and doesn't affect the leaderboard).
  static const _vetoReasons = [
    ('not_shown', "Doesn't show the result"),
    ('wrong_result', 'Wrong result'),
    ('stale_proof', 'Old or unrelated proof'),
    ('other', 'Other'),
  ];

  Future<void> _vetoProof(RaceProof proof) async {
    final reason = await showV13Sheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          V13.gapMd,
          V13.pagePad,
          V13.gapXl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Veto this proof?', style: V13.sectionHead),
            const SizedBox(height: V13.gapSm),
            Text(
              'If enough racers agree, it stops counting on the leaderboard.',
              style: V13.body.copyWith(color: V13.muted),
            ),
            const SizedBox(height: V13.gapLg),
            for (final (value, label) in _vetoReasons) ...[
              V13Button.secondary(
                label: label,
                fullWidth: true,
                onPressed: () => Navigator.of(ctx).pop(value),
              ),
              const SizedBox(height: V13.gapSm),
            ],
          ],
        ),
      ),
    );
    if (!mounted || reason == null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(raceControllerProvider.notifier)
          .vetoProof(widget.raceId, widget.proofId, reason: reason);
      // Refresh so vetoed/disputed state and any leaderboard change show up.
      await _load();
      if (mounted) {
        showV13Toast(
          context,
          result.vetoed
              ? 'Proof vetoed — it no longer counts.'
              : result.alreadyVoted
              ? 'You already vetoed this proof.'
              : 'Veto counted — ${result.vetoCount} of ${result.threshold} needed.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showV13Toast(context, friendlyApiError(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showV13Toast(context, 'Could not veto proof. Try again.');
      }
    }
  }

  Future<void> _reportProof(RaceProof proof) async {
    final controller = TextEditingController();
    final reason = await showV13Sheet<String>(
      context,
      builder: (ctx) => _ReportMoveSheet(controller: controller),
    );
    if (!mounted || reason == null) return;
    try {
      await ref
          .read(crewRepositoryProvider)
          .reportContent(proof.id, reason: reason);
      if (mounted) {
        showV13Toast(context, 'Thanks — our team will take a look.');
      }
    } on ApiException catch (e) {
      if (mounted) showV13Toast(context, friendlyApiError(e));
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't send that. Try again.");
      }
    }
  }

  // Evidence fetch needs the Bearer header — the URL alone won't serve
  // media to anyone who guesses the path.
  ImageProvider? _evidenceImage(RaceProof proof) {
    final media = proof.mediaUrl;
    final token = _accessToken;
    if (media == null || token == null) return null;
    return CachedNetworkImageProvider(
      media.startsWith('http') ? media : '$kNuvoApiBase$media',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  String _viewerStatus(RaceProof proof) {
    if (proof.vetoState == 'vetoed') {
      return 'Proof vetoed — does not count on the leaderboard.';
    }
    if (proof.vetoState == 'disputed') {
      return 'Proof disputed — ${proof.vetoCount} veto${proof.vetoCount == 1 ? '' : 's'} so far.';
    }
    return switch (proof.verificationStatus) {
      'accepted' ||
      'verified' ||
      'ai_verified' => 'Accepted — counts on the leaderboard.',
      'rejected' => 'Rejected — does not count on the leaderboard.',
      _ => 'Waiting on the race creator\'s review.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final race = _race;
    final proof = _proof;
    final isOwner = race?.creatorId == user?.id;
    final isParticipant =
        user != null && (race?.isParticipant(user.id) ?? false);

    // View ≠ review: any active participant can inspect the proof; only the
    // creator sees decision controls. Non-participants get nothing.
    final canView = isOwner || isParticipant;

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: isOwner ? 'Review move' : 'Proof',
              onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
            ),
            Expanded(
              child: V13AsyncView<Race>.state(
                status: _loading
                    ? V13AsyncStatus.loading
                    : race == null
                    ? V13AsyncStatus.error
                    : proof == null || !canView
                    ? V13AsyncStatus.empty
                    : V13AsyncStatus.data,
                dataValue: race,
                errorTitle: _error ?? 'Could not load move review',
                emptyTitle: 'Move not found',
                emptyBody:
                    'It may have been removed, or it is not yours to see.',
                emptyIcon: Icons.flag_outlined,
                emptyAction: V13Button.secondary(
                  label: 'Back to race',
                  onPressed: () => context.go('/race/${widget.raceId}'),
                ),
                onRetry: _load,
                builder: (data) => _body(data, proof!, isOwner, user?.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Race race, RaceProof proof, bool isOwner, String? uid) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXxl * 2,
      ),
      children: [
        _MoveSummaryCard(
          proof: proof,
          race: race,
          evidenceImage: _evidenceImage(proof),
          onFaceTap: () => openPerson(context, ref, proof.userId),
        ),
        const SizedBox(height: V13.gapXl),
        // Action visibility mirrors the backend contract so the UI never
        // offers a mutation that will 409:
        //  - creator review controls only while the proof is HELD (pending →
        //    'needs_review'/'submitted'); counted proof is disputed through
        //    veto, vetoed proof is final;
        //  - nobody reviews or vetoes their own proof;
        //  - any participant (creator included) can veto another racer's
        //    non-vetoed proof.
        if (!raceProofIsReviewable(race, proof, uid)) ...[
          Text(
            _viewerStatus(proof),
            style: V13.body.copyWith(color: V13.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V13.gapMd),
          // Race-truth action: other racers can dispute whether this proof
          // should count. Own vetoed proofs get the replacement path — the
          // old record stays for audit.
          if (raceProofIsVetoable(race, proof, uid)) ...[
            V13Button.secondary(
              label: proof.viewerVoted ? 'You vetoed this proof' : 'Veto proof',
              icon: Icons.gavel_rounded,
              fullWidth: true,
              onPressed: _saving || proof.viewerVoted
                  ? null
                  : () => _vetoProof(proof),
            ),
            const SizedBox(height: V13.gapMd),
          ],
          if (proof.userId == uid && proof.vetoState == 'vetoed') ...[
            V13Button.primary(
              label: 'Submit new proof',
              icon: Icons.add_a_photo_outlined,
              fullWidth: true,
              onPressed: () => openSubmitProof(context, ref, race),
            ),
            const SizedBox(height: V13.gapMd),
          ],
          if (proof.userId != uid)
            Center(
              child: V13Button.ghost(
                label: 'Report this move',
                onPressed: () => _reportProof(proof),
              ),
            ),
        ] else ...[
          _NoteInput(
            controller: _summaryController,
            label: 'Review note (optional)',
            hint: 'Add a note for the submitter',
          ),
          if (_error != null) ...[
            const SizedBox(height: V13.gapMd),
            Text(_error!, style: V13.caption.copyWith(color: V13.danger)),
          ],
          const SizedBox(height: V13.gapXl),
          Text('Proof decision', style: V13.sectionHead),
          const SizedBox(height: V13.gapMd),
          V13Button.primary(
            label: 'Accept proof',
            icon: Icons.check_rounded,
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : () => _review('accepted'),
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.secondary(
            label: 'Ask for another proof',
            icon: Icons.rate_review_rounded,
            fullWidth: true,
            onPressed: _saving ? null : () => _review('needs_review'),
          ),
          const SizedBox(height: V13.gapSm),
          Text(
            'The racer can submit another proof after reading your note.',
            style: V13.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.danger(
            label: 'Reject proof',
            icon: Icons.close_rounded,
            fullWidth: true,
            onPressed: _saving ? null : () => _review('rejected'),
          ),
          const SizedBox(height: V13.gapSm),
          Text(
            'This declines the proof and keeps it out of the leaderboard.',
            style: V13.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ── Move summary card ────────────────────────────────────────────────────────

class _MoveSummaryCard extends StatelessWidget {
  const _MoveSummaryCard({
    required this.proof,
    required this.race,
    required this.onFaceTap,
    this.evidenceImage,
  });

  final RaceProof proof;
  final Race race;
  final VoidCallback onFaceTap;

  /// Authed evidence image — null when no media or the viewer can't fetch it.
  final ImageProvider? evidenceImage;

  Color get _statusColor => switch (proof.verificationStatus) {
    'accepted' || 'verified' || 'ai_verified' => V13.mint,
    'rejected' => V13.coral,
    'needs_review' || 'submitted' => V13.sun,
    _ => V13.sky,
  };

  String get _statusLabel {
    final s = proof.verificationStatus.replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final valueLabel = proof.value == null
        ? null
        : race.unit == null
        ? '+${proof.value}'
        : '+${proof.value} ${race.unit}';

    return V13Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13Face(
                photoUrl: proof.profilePhotoUrl,
                size: 44,
                name: proof.displayName,
                onTap: onFaceTap,
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proof.displayName,
                      style: V13.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(race.title, style: V13.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          Wrap(
            spacing: V13.gapSm,
            runSpacing: V13.gapSm,
            children: [
              V13Pill(label: _statusLabel, color: _statusColor),
              V13Pill(
                label: proof.proofType == 'ai_motion' ? 'Camera' : 'Manual',
                color: V13.card,
              ),
            ],
          ),
          if (valueLabel != null) ...[
            const SizedBox(height: V13.gapMd),
            Text(valueLabel, style: V13.number.copyWith(color: V13.blue)),
          ],
          if (evidenceImage != null) ...[
            const SizedBox(height: V13.gapMd),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(V13.radiusTile),
                border: Border.all(color: V13.navy, width: V13.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: evidenceImage!,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (proof.note != null) ...[
            const SizedBox(height: V13.gapMd),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(V13.gapMd),
              decoration: BoxDecoration(
                color: V13.bg,
                border: Border.all(color: V13.divider, width: V13.outline),
                borderRadius: BorderRadius.circular(V13.radiusTile),
              ),
              child: Text(proof.note!, style: V13.body),
            ),
          ],
        ],
      ),
    );
  }
}

/// Multi-line note field in V13TextInput's chrome (that widget is single-line
/// only, so multi-line fields use this thin wrapper).
class _NoteInput extends StatelessWidget {
  const _NoteInput({required this.controller, required this.label, this.hint});

  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: V13.bodyStrong),
        const SizedBox(height: V13.gapSm),
        TextField(
          controller: controller,
          maxLines: 4,
          style: V13.body,
          cursorColor: V13.blue,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: V13.body.copyWith(color: V13.muted),
            filled: true,
            fillColor: V13.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V13.radiusButton),
              borderSide: const BorderSide(color: V13.navy, width: V13.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V13.radiusButton),
              borderSide: const BorderSide(color: V13.blue, width: V13.outline),
            ),
          ),
        ),
      ],
    );
  }
}

/// The report sheet — title, explainer, optional details, send.
class _ReportMoveSheet extends StatelessWidget {
  const _ReportMoveSheet({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report this move?', style: V13.sectionHead),
          const SizedBox(height: V13.gapSm),
          Text(
            'What’s wrong? This goes to the Nuvo review team.',
            style: V13.body.copyWith(color: V13.muted),
          ),
          const SizedBox(height: V13.gapMd),
          V13Card(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: 2,
            ),
            child: TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 500,
              style: V13.body,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Optional details',
                hintStyle: TextStyle(color: V13.muted),
                counterStyle: TextStyle(color: V13.muted),
              ),
            ),
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.primary(
            label: 'Send report',
            icon: Icons.flag_outlined,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
  }
}
