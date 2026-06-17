import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_card.dart';
import '../../../core/widgets/nuvo_chip.dart';
import '../application/challenge_providers.dart';
import '../domain/models/challenge.dart';
import '../domain/models/participant.dart';

/// Start a race — inside the bottom nav shell (no Scaffold here).
class CreateChallengeScreen extends ConsumerStatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  ConsumerState<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState
    extends ConsumerState<CreateChallengeScreen> {
  final _titleController = TextEditingController();
  ChallengeCategory _category = ChallengeCategory.fitness;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 14));
  double _entryFee = 0;
  _StakeType _stakeType = _StakeType.bragging;
  _ProofMethod _proof = _ProofMethod.wearable;
  bool _submitting = false;

  double get _previewPrizePool {
    const platformCut = 0.10;
    return _entryFee * (1 - platformCut);
  }

  String get _stakeLabel => switch (_stakeType) {
        _StakeType.bragging => 'Bragging rights',
        _StakeType.forfeit => 'Forfeit challenge',
        _StakeType.sharedPot =>
          _entryFee == 0 ? 'Shared pot' : '\$${_entryFee.toInt()} entry',
      };

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        // Header
        Text('Start a race', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 4),
        Text(
          'Pick a goal, set the stakes, pull in your crew.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),

        // Section 1: What are you racing for?
        const _SectionLabel(label: 'WHAT ARE YOU RACING FOR?'),
        const SizedBox(height: 12),
        _PresetsWrap(
          onSelect: (preset) => setState(() => _titleController.text = preset),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          style: AppTextStyles.bodyLarge,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Or type your own goal…',
          ),
        ),
        const SizedBox(height: 24),

        // Category
        const _SectionLabel(label: 'CATEGORY'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in ChallengeCategory.values)
              NuvoChip(
                label: c.label,
                selected: _category == c,
                onTap: () => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Section 2: Set the finish line
        const _SectionLabel(label: 'SET THE FINISH LINE'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Start',
                value: _start,
                onChanged: (d) => setState(() => _start = d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'End',
                value: _end,
                onChanged: (d) => setState(() => _end = d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          Formatters.dateRange(_start, _end),
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 24),

        // Section 3: Set the stakes
        const _SectionLabel(label: 'SET THE STAKES'),
        const SizedBox(height: 10),
        _StakesSelector(
          selected: _stakeType,
          onChanged: (t) => setState(() {
            _stakeType = t;
            if (t != _StakeType.sharedPot) _entryFee = 0;
          }),
        ),
        if (_stakeType == _StakeType.sharedPot) ...[
          const SizedBox(height: 14),
          _EntryFeeCard(
            entryFee: _entryFee,
            prizePool: _previewPrizePool,
            onChanged: (v) => setState(() => _entryFee = v),
          ),
        ],
        const SizedBox(height: 24),

        // Section 4: Proof method
        const _SectionLabel(label: 'PROOF METHOD'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _ProofMethod.values)
              NuvoChip(
                label: p.label,
                selected: _proof == p,
                onTap: () => setState(() => _proof = p),
              ),
          ],
        ),
        const SizedBox(height: 28),

        // Live invite preview card
        const _SectionLabel(label: 'INVITE PREVIEW'),
        const SizedBox(height: 10),
        _LivePreviewCard(
          title: _titleController.text,
          durationDays: _end.difference(_start).inDays,
          stakeLabel: _stakeLabel,
          proofLabel: _proof.label,
        ),
        const SizedBox(height: 28),

        NuvoPrimaryButton(
          label: _submitting ? 'Starting race…' : 'Start race',
          icon: Icons.flag_rounded,
          expand: true,
          loading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        const SizedBox(height: 12),
        NuvoSecondaryButton(
          label: 'Invite crew first',
          icon: Icons.people_rounded,
          expand: true,
          onPressed: () => context.go('/crew'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your race a name.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final repo = ref.read(challengeRepositoryProvider);
    final draft = Challenge(
      id: '',
      title: _titleController.text.trim(),
      category: _category,
      participants: const [Participant(id: 'me', username: 'you')],
      startDate: _start,
      endDate: _end,
      entryFee: _entryFee,
      prizeType: _entryFee == 0 ? PrizeType.glory : PrizeType.usd,
    );
    await repo.create(draft);
    if (!mounted) return;
    ref.invalidate(activeChallengesProvider);
    context.go('/arena');
  }
}

enum _StakeType { bragging, forfeit, sharedPot }

extension on _StakeType {
  String get label => switch (this) {
        _StakeType.bragging => 'Bragging rights',
        _StakeType.forfeit => 'Forfeit',
        _StakeType.sharedPot => 'Shared pot',
      };
  IconData get icon => switch (this) {
        _StakeType.bragging => Icons.workspace_premium_rounded,
        _StakeType.forfeit => Icons.warning_amber_rounded,
        _StakeType.sharedPot => Icons.attach_money_rounded,
      };
}

enum _ProofMethod { wearable, aiCamera, peerJudged, selfReport }

extension on _ProofMethod {
  String get label => switch (this) {
        _ProofMethod.wearable => 'Wearable',
        _ProofMethod.aiCamera => 'AI camera',
        _ProofMethod.peerJudged => 'Peer judged',
        _ProofMethod.selfReport => 'Self report',
      };
}

// ---------------------------------------------------------------------------
// Live invite preview card
// ---------------------------------------------------------------------------

class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({
    required this.title,
    required this.durationDays,
    required this.stakeLabel,
    required this.proofLabel,
  });

  final String title;
  final int durationDays;
  final String stakeLabel;
  final String proofLabel;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title.trim().isNotEmpty;
    final days = durationDays.clamp(1, 9999);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.sectionBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_rounded,
                  size: 13, color: NuvoColors.muted),
              const SizedBox(width: 6),
              Text(
                'How your invite will look',
                style: AppTextStyles.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mock invite card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akshay challenged you to',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: NuvoColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  hasTitle ? title.trim() : 'your goal here',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: hasTitle ? NuvoColors.navy : NuvoColors.border,
                    fontStyle:
                        hasTitle ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '$days day${days == 1 ? '' : 's'} · $proofLabel',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Stakes: $stakeLabel',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: NuvoColors.muted),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: NuvoColors.sectionBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Accept race',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: NuvoColors.muted),
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

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.labelSmall.copyWith(
        color: NuvoColors.muted,
        letterSpacing: 0.8,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preset cards — Wrap layout (fixes overflow)
// ---------------------------------------------------------------------------

class _PresetsWrap extends StatelessWidget {
  const _PresetsWrap({required this.onSelect});
  final void Function(String) onSelect;

  static const _presets = [
    '100 pushups every day',
    'Wake at 5:30 AM daily',
    'Read 30 min a day',
    'No sugar for 30 days',
    'Ship a project in 7 days',
    'Walk 10k steps a day',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _presets
          .map((p) => _PresetCard(label: p, onTap: () => onSelect(p)))
          .toList(),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NuvoColors.sectionBlue,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bolt_rounded, size: 14, color: NuvoColors.blue),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.navy),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stakes selector
// ---------------------------------------------------------------------------

class _StakesSelector extends StatelessWidget {
  const _StakesSelector({required this.selected, required this.onChanged});
  final _StakeType selected;
  final ValueChanged<_StakeType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _StakeType.values.map((type) {
        final isSelected = type == selected;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? NuvoColors.bluePale : NuvoColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    isSelected ? NuvoColors.blue : NuvoColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  type.icon,
                  size: 18,
                  color: isSelected ? NuvoColors.blue : NuvoColors.muted,
                ),
                const SizedBox(width: 12),
                Text(
                  type.label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color:
                        isSelected ? NuvoColors.navy : NuvoColors.muted,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: NuvoColors.blue),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry fee slider (shared pot only)
// ---------------------------------------------------------------------------

class _EntryFeeCard extends StatelessWidget {
  const _EntryFeeCard({
    required this.entryFee,
    required this.prizePool,
    required this.onChanged,
  });
  final double entryFee;
  final double prizePool;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final isFree = entryFee == 0;

    return NuvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Entry fee', style: AppTextStyles.titleMedium),
              const Spacer(),
              Text(
                isFree ? 'Free' : Formatters.money(entryFee),
                style: AppTextStyles.titleMedium.copyWith(
                  color: NuvoColors.blue,
                ),
              ),
            ],
          ),
          Slider(
            value: entryFee,
            min: 0,
            max: 500,
            divisions: 50,
            label: isFree ? 'Free' : Formatters.money(entryFee),
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$0', style: AppTextStyles.labelSmall),
              Text('\$500', style: AppTextStyles.labelSmall),
            ],
          ),
          if (!isFree) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.attach_money_rounded,
                    size: 16, color: NuvoColors.mint),
                const SizedBox(width: 8),
                Text('Projected prize pool',
                    style: AppTextStyles.bodyMedium),
                const Spacer(),
                Text(
                  Formatters.money(prizePool),
                  style: AppTextStyles.titleMedium
                      .copyWith(color: NuvoColors.mint),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NuvoColors.sectionBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: NuvoColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demo only. Real-money payouts are coming soon.',
                    style: AppTextStyles.bodySmall,
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

// ---------------------------------------------------------------------------
// Date field
// ---------------------------------------------------------------------------

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: NuvoColors.sectionBlue,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: NuvoColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${value.month.toString().padLeft(2, '0')}/'
                    '${value.day.toString().padLeft(2, '0')}/'
                    '${value.year}',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
