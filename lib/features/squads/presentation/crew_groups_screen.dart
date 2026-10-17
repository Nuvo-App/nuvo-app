import 'package:flutter/material.dart';
import 'package:nuvo/core/widgets/nuvo_fade_scroll.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../social/presentation/theme_ink.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/live_refresh.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';
import '../application/squad_controller.dart';
import '../data/squad_api.dart';

String _messageFor(Object e) =>
    e is ApiException ? e.message : 'Something went wrong. Try again.';

/// Back that never dead-ends: pops when there is history, otherwise lands on
/// the Crew tab (deep links and cold starts have nothing to pop to).
void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/pass');
  }
}

/// NuvoPage does not inset its topBar for the status bar / Dynamic Island, so
/// the header owns the top safe area itself.
Widget _topBar(BuildContext context, String title, {Widget? trailing}) =>
    SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NuvoSpacing.sm,
          NuvoSpacing.xs,
          NuvoSpacing.lg,
          NuvoSpacing.xs,
        ),
        child: NuvoBackHeader(
          title: title,
          onBack: () => _leave(context),
          trailing: trailing,
        ),
      ),
    );

const double _kSide = NuvoSpacing.lg;

// ─────────────────────────────────────────────────────────────────────────────
// /crews — the crews I'm in
// ─────────────────────────────────────────────────────────────────────────────

class CrewGroupsScreen extends ConsumerStatefulWidget {
  const CrewGroupsScreen({super.key});

  @override
  ConsumerState<CrewGroupsScreen> createState() => _CrewGroupsScreenState();
}

class _CrewGroupsScreenState extends ConsumerState<CrewGroupsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred: a provider may not be modified while the tree is building.
    Future(() {
      if (!mounted) return;
      final c = ref.read(squadControllerProvider.notifier);
      c.load();
      c.revalidate();
    });
  }

  Future<void> _load() => ref.read(squadControllerProvider.notifier).refresh();

  Future<void> _start() async {
    final group = await showModalBottomSheet<CrewGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CrewInputSheet(mode: _SheetMode.create),
    );
    if (group == null || !mounted) return;
    if (mounted) context.push('/crews/${group.id}');
  }

  Future<void> _join() async {
    final joined = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CrewInputSheet(mode: _SheetMode.join),
    );
    if (joined != true || !mounted) return;
    // Joining pulls me into the crew's running races — refresh race lists too.
    ref.read(raceControllerProvider.notifier).loadRaces(force: true);
  }

  void _scan() => context.push('/scan');

  @override
  Widget build(BuildContext context) {
    final squads = ref.watch(squadControllerProvider);
    final groups = squads.groups;
    final error = squads.error;
    final Widget body;
    if (groups == null && error != null) {
      body = NuvoErrorState(message: error, onRetry: _load);
    } else if (groups == null) {
      body = const Center(child: NuvoLoadingIndicator());
    } else if (groups.isEmpty) {
      body = LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: NuvoEmptyState(
                icon: Icons.groups_rounded,
                leading: const NuvoCrewIcon(size: 28, semanticLabel: null),
                title: 'Race with a crew',
                body:
                    'Start a crew, share the code, and every race you '
                    'bring to it lands on one leaderboard.',
                ctaLabel: 'Start a crew',
                onCta: _start,
                secondaryLabel: 'Join with a code',
                onSecondary: _join,
                align: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: NuvoFadeScroll(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              _kSide,
              NuvoSpacing.md,
              _kSide,
              24,
            ),
            children: [
              _AddPanel(onStart: _start, onJoin: _join, onScan: _scan),
              const SizedBox(height: NuvoSpacing.lg),
              for (final g in groups) _GroupCard(group: g),
            ],
          ),
        ),
      );
    }
    return LiveRefresh(
      onRefresh: () => ref.read(squadControllerProvider.notifier).refresh(),
      child: NuvoPage(topBar: _topBar(context, 'Crews'), child: body),
    );
  }
}

/// The one place crews are added: start one, join with a code, or scan a
/// crew's QR. An outlined card in the app's physical style, above the list.
class _AddPanel extends StatelessWidget {
  const _AddPanel({
    required this.onStart,
    required this.onJoin,
    required this.onScan,
  });
  final VoidCallback onStart;
  final VoidCallback onJoin;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.15;
    final start = NuvoPrimaryButton(
      label: 'Start a crew',
      icon: Icons.add_rounded,
      expand: true,
      onPressed: onStart,
    );
    final join = NuvoOutlineButton(
      label: 'Join with a code',
      icon: Icons.login_rounded,
      expand: true,
      onPressed: onJoin,
    );
    return Container(
      key: const ValueKey('crew-add-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: c.border, width: 2),
        boxShadow: AppShadows.hardOffset(c.inkShadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a crew',
            style: AppTextStyles.titleMedium.copyWith(color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'Start your own, or pull in with a code or QR.',
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 12),
          if (stacked) ...[
            start,
            const SizedBox(height: 8),
            join,
          ] else
            Row(
              children: [
                Expanded(child: start),
                const SizedBox(width: 10),
                Expanded(child: join),
              ],
            ),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Scan a crew QR code',
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('crew-scan-qr'),
              borderRadius: BorderRadius.circular(NuvoRadii.sm),
              onTap: onScan,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 20,
                      color: c.accent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Scan a crew QR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: c.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small crew-code pill used on list cards and the detail share card.
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    if (code.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: c.border),
      ),
      child: Text(
        code,
        maxLines: 1,
        style: AppTextStyles.labelMedium.copyWith(
          color: c.inkMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final CrewGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final races =
        '${group.raceCount} ${group.raceCount == 1 ? 'race' : 'races'}';
    final people = '${group.memberCount} in crew';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 4),
      child: Semantics(
        button: true,
        label: '${group.name}, $people, $races, code ${group.joinCode}',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NuvoRadii.sm),
            boxShadow: AppShadows.hardOffset(c.inkShadow),
          ),
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(NuvoRadii.sm),
              onTap: () => context.push('/crews/${group.id}'),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NuvoRadii.sm),
                  border: Border.all(color: c.border, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.panel,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const NuvoCrewIcon(size: 26, semanticLabel: null),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: c.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '$people · $races',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: c.inkMuted,
                                ),
                              ),
                              _CodeChip(code: group.joinCode),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Start / join sheet
// ─────────────────────────────────────────────────────────────────────────────

enum _SheetMode { create, join }

class _CrewInputSheet extends ConsumerStatefulWidget {
  const _CrewInputSheet({required this.mode});
  final _SheetMode mode;

  @override
  ConsumerState<_CrewInputSheet> createState() => _CrewInputSheetState();
}

class _CrewInputSheetState extends ConsumerState<_CrewInputSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isCreate => widget.mode == _SheetMode.create;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _controller.text.trim();
    if (_isCreate ? text.length < 2 : text.isEmpty) {
      setState(
        () => _error = _isCreate
            ? 'Give your crew a name (2 characters or more).'
            : 'Enter the crew code.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final squads = ref.read(squadControllerProvider.notifier);
    try {
      if (_isCreate) {
        final group = await squads.create(text);
        if (mounted) Navigator.of(context).pop(group);
      } else {
        await squads.join(text);
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final router = GoRouter.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: _isCreate
                      ? const NuvoCrewIcon(size: 28, semanticLabel: null)
                      : Icon(Icons.login_rounded, color: c.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isCreate ? 'Start a crew' : 'Join a crew',
                        style: AppTextStyles.titleLarge.copyWith(color: c.ink),
                      ),
                      Text(
                        _isCreate
                            ? 'Name it, then share the code or QR.'
                            : 'Type the code or scan the crew QR.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('crew-input'),
              controller: _controller,
              autofocus: true,
              maxLength: _isCreate ? 40 : 12,
              textAlign: _isCreate ? TextAlign.start : TextAlign.center,
              style: _isCreate
                  ? null
                  : AppTextStyles.titleLarge.copyWith(
                      color: c.ink,
                      letterSpacing: 4,
                    ),
              textCapitalization: _isCreate
                  ? TextCapitalization.words
                  : TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _isCreate ? 'Crew name' : 'Crew code',
                counterText: '',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            NuvoPrimaryButton(
              label: _isCreate ? 'Start crew' : 'Join crew',
              expand: true,
              loading: _busy,
              onPressed: _submit,
            ),
            if (!_isCreate) ...[
              const SizedBox(height: 10),
              NuvoOutlineButton(
                label: 'Scan crew QR',
                icon: Icons.qr_code_scanner_rounded,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  router.push('/scan');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// /crews/:id — the crew leaderboard
// ─────────────────────────────────────────────────────────────────────────────

class CrewGroupDetailScreen extends ConsumerStatefulWidget {
  const CrewGroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<CrewGroupDetailScreen> createState() =>
      _CrewGroupDetailScreenState();
}

class _CrewGroupDetailScreenState extends ConsumerState<CrewGroupDetailScreen> {
  String? _actionError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future(() {
      if (!mounted) return;
      final c = ref.read(squadControllerProvider.notifier);
      c.loadDetail(widget.groupId);
      c.revalidateDetail(widget.groupId);
    });
  }

  Future<void> _load() =>
      ref.read(squadControllerProvider.notifier).refreshDetail(widget.groupId);

  Future<void> _bringRace() async {
    final detail = ref.read(squadControllerProvider).details[widget.groupId];
    final me = ref.read(authControllerProvider).user;
    if (detail == null || me == null) return;
    final linked = detail.races.map((r) => r.id).toSet();
    final mine = ref
        .read(raceControllerProvider)
        .races
        .where(
          (r) =>
              r.creatorId == me.id &&
              r.status == 'active' &&
              !linked.contains(r.id),
        )
        .toList();

    if (mine.isEmpty) {
      // Nothing to bring yet — start a race, then come back.
      context.push('/races/new');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.themeColors;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'Bring a race to the crew',
                style: AppTextStyles.titleLarge.copyWith(color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Everyone in the crew is added to the race.',
                style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: 8),
              for (final race in mine)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_rounded),
                  title: Text(race.displayTitle),
                  onTap: () => Navigator.of(ctx).pop(race.id),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_rounded),
                title: const Text('Start a new race'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/races/new');
                },
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref
          .read(squadControllerProvider.notifier)
          .addRace(widget.groupId, picked);
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
    } catch (e) {
      if (mounted) setState(() => _actionError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveCrew() async {
    final ok = await showNuvoConfirmDialog(
      context,
      title: 'Leave this crew?',
      message: 'You stay in races you already joined.',
      confirmLabel: 'Leave crew',
    );
    if (ok != true) return;
    try {
      await ref.read(squadControllerProvider.notifier).leave(widget.groupId);
      if (mounted) _leave(context);
    } catch (e) {
      if (mounted) setState(() => _actionError = _messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final squads = ref.watch(squadControllerProvider);
    final detail = squads.details[widget.groupId];
    final error = squads.detailErrors[widget.groupId];
    final c = context.themeColors;

    if (detail == null) {
      return NuvoPage(
        topBar: _topBar(context, 'Crew'),
        child: error != null
            ? NuvoErrorState(message: error, onRetry: _load)
            : const Center(child: NuvoLoadingIndicator()),
      );
    }

    return LiveRefresh(
      onRefresh: () => ref
          .read(squadControllerProvider.notifier)
          .refreshDetail(widget.groupId),
      child: NuvoPage(
        topBar: _topBar(
          context,
          detail.group.name,
          trailing: PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_horiz_rounded, color: c.ink),
            onSelected: (_) => _leaveCrew(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'leave', child: Text('Leave crew')),
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: NuvoFadeScroll(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                _kSide,
                NuvoSpacing.md,
                _kSide,
                32 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                // Leaderboard first — it is the point of the crew.
                Row(
                  children: [
                    Text(
                      'Leaderboard',
                      style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                    ),
                    const SizedBox(width: NuvoSpacing.sm),
                    Expanded(
                      child: Text(
                        '5 · 3 · 2 pts, 1 per proof',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NuvoSpacing.md),
                if (detail.races.isEmpty)
                  const _InlineNote(
                    icon: Icons.flag_outlined,
                    text:
                        'No races yet. Bring a race to start the leaderboard.',
                  )
                else if (detail.standings.every((s) => s.points == 0))
                  const _InlineNote(
                    icon: Icons.bolt_rounded,
                    text: 'No proof yet. The first proof takes the lead.',
                  ),
                if (_showPodium(detail.standings)) ...[
                  _Podium(standings: detail.standings.take(3).toList()),
                  const SizedBox(height: NuvoSpacing.sm),
                  for (final s in detail.standings.skip(3))
                    _StandingRow(standing: s),
                ] else
                  for (final s in detail.standings) _StandingRow(standing: s),
                const SizedBox(height: NuvoSpacing.sm),
                NuvoPrimaryButton(
                  label: 'Bring a race to the crew',
                  icon: Icons.flag_rounded,
                  expand: true,
                  loading: _busy,
                  onPressed: _bringRace,
                ),
                if (_actionError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _actionError!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.dangerInk,
                    ),
                  ),
                ],
                const SizedBox(height: NuvoSpacing.lg),
                _CodeCard(group: detail.group),
                if (detail.races.isNotEmpty) ...[
                  const SizedBox(height: NuvoSpacing.xxl),
                  Text(
                    'Crew races',
                    style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: NuvoSpacing.xs),
                  for (final r in detail.races) _RaceRow(race: r),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _showPodium(List<CrewGroupStanding> s) =>
      s.length >= 3 && s.any((e) => e.points > 0);
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.inkSubtle),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.group});
  final CrewGroup group;

  /// What the QR carries; `NuvoDestination` parses it back to the code.
  String get _link => 'https://getnuvo.net/c/${group.joinCode}';

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      key: const ValueKey('crew-code-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: c.border, width: 2),
        boxShadow: AppShadows.hardOffset(c.inkShadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pull in your crew',
            style: AppTextStyles.titleMedium.copyWith(color: c.ink),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // Scanners need the white quiet zone in both themes.
                color: NuvoColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border, width: 2),
              ),
              child: QrImageView(
                key: const ValueKey('crew-qr'),
                data: _link,
                version: QrVersions.auto,
                size: 168,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: NuvoColors.navy,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: NuvoColors.navy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Crew code',
              style: AppTextStyles.labelMedium.copyWith(color: c.inkMuted),
            ),
          ),
          Center(
            child: Text(
              group.joinCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                color: c.ink,
                letterSpacing: 4,
              ),
            ),
          ),
          Center(
            child: Text(
              'Scan or enter this code to join',
              style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NuvoOutlineButton(
                  label: 'Copy code',
                  icon: Icons.copy_rounded,
                  expand: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: group.joinCode));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Crew code copied')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NuvoPrimaryButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  onPressed: () => Share.share(
                    'Join my crew "${group.name}" on Nuvo. Crew code: '
                    '${group.joinCode}\n$_link',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `/crews/join/:code` — where a scanned crew QR or shared link lands. It
/// confirms before joining; scanning never joins on its own.
class CrewJoinScreen extends ConsumerStatefulWidget {
  const CrewJoinScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<CrewJoinScreen> createState() => _CrewJoinScreenState();
}

class _CrewJoinScreenState extends ConsumerState<CrewJoinScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(squadControllerProvider.notifier).join(widget.code);
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
      if (!mounted) return;
      final joined = ref
          .read(squadControllerProvider)
          .groups
          ?.where((g) => g.joinCode.toUpperCase() == widget.code.toUpperCase())
          .firstOrNull;
      if (joined != null) {
        context.pushReplacement('/crews/${joined.id}');
      } else {
        context.pushReplacement('/crews');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return NuvoPage(
      topBar: _topBar(context, 'Join a crew'),
      child: Padding(
        padding: const EdgeInsets.all(_kSide),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NuvoCrewIcon(size: 56, semanticLabel: null),
              const SizedBox(height: 16),
              Text(
                'Join this crew?',
                style: AppTextStyles.titleLarge.copyWith(color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(
                widget.code,
                style: AppTextStyles.titleLarge.copyWith(
                  color: c.ink,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You will join its leaderboard and its running races.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.dangerInk,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              NuvoPrimaryButton(
                label: 'Join crew',
                expand: true,
                loading: _busy,
                onPressed: _join,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color? _medalFor(int rank) => switch (rank) {
  1 => NuvoColors.sunshine,
  2 => const Color(0xFFB8C2D6),
  3 => NuvoColors.orange,
  _ => null,
};

/// Top three as a podium: 2nd | 1st | 3rd, the leader on the tallest step.
class _Podium extends StatelessWidget {
  const _Podium({required this.standings});
  final List<CrewGroupStanding> standings;

  @override
  Widget build(BuildContext context) {
    final byRank = [standings[1], standings[0], standings[2]];
    return Padding(
      padding: const EdgeInsets.only(bottom: NuvoSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final s in byRank) Expanded(child: _PodiumStep(standing: s)),
        ],
      ),
    );
  }
}

class _PodiumStep extends StatelessWidget {
  const _PodiumStep({required this.standing});
  final CrewGroupStanding standing;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final medal = standing.points > 0 ? _medalFor(standing.rank) : null;
    final first = standing.rank == 1;
    final height = switch (standing.rank) {
      1 => 64.0,
      2 => 48.0,
      _ => 40.0,
    };
    return Semantics(
      label:
          'Rank ${standing.rank}, ${standing.displayName}, '
          '${standing.points} points',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NuvoAvatar(
              initials: standing.initials,
              size: first ? NuvoAvatarSizes.lg : NuvoAvatarSizes.md,
              photoUrl: standing.profilePhotoUrl,
            ),
            const SizedBox(height: 6),
            Text(
              standing.isYou ? 'You' : standing.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelLarge.copyWith(color: c.ink),
            ),
            Text(
              '${standing.points} pts',
              style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 6),
            Container(
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal ?? c.panel,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                border: standing.isYou
                    ? Border.all(color: NuvoColors.blue, width: 1.5)
                    : null,
              ),
              child: Text(
                '${standing.rank}',
                style: AppTextStyles.titleLarge.copyWith(
                  color: medal != null ? NuvoColors.navy : c.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.standing});
  final CrewGroupStanding standing;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final medal = standing.points > 0 ? _medalFor(standing.rank) : null;
    final lead = standing.points > 0 && standing.rank == 1;
    final detail = standing.races == 0
        ? 'No proof yet'
        : '${standing.races} ${standing.races == 1 ? 'race' : 'races'}'
              '${standing.wins > 0 ? ' · ${standing.wins} ${standing.wins == 1 ? 'win' : 'wins'}' : ''}';
    return Semantics(
      label:
          'Rank ${standing.rank}, ${standing.displayName}, '
          '${standing.points} points',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: standing.isYou ? c.panel : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: lead ? NuvoColors.blue : c.border,
            width: lead || standing.isYou ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal ?? Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${standing.rank}',
                style: AppTextStyles.labelLarge.copyWith(
                  color: medal != null ? NuvoColors.navy : c.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            NuvoAvatar(
              initials: standing.initials,
              size: NuvoAvatarSizes.sm,
              photoUrl: standing.profilePhotoUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    standing.isYou
                        ? '${standing.displayName} (you)'
                        : standing.displayName,
                    style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    detail,
                    style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${standing.points}',
              style: AppTextStyles.titleMedium.copyWith(color: c.ink),
            ),
            const SizedBox(width: 3),
            Text(
              'pts',
              style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceRow extends StatelessWidget {
  const _RaceRow({required this.race});
  final CrewGroupRace race;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final live = race.status == 'active';
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push('/race/${race.id}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      race.title,
                      style: AppTextStyles.bodyLarge.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      live ? 'Racing now' : 'Finished',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: live ? context.successInk : c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
