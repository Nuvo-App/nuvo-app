import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';
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

Widget _topBar(BuildContext context, String title, {Widget? trailing}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: NuvoBackHeader(
        title: title,
        onBack: () => _leave(context),
        trailing: trailing,
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// /crews — the crews I'm in
// ─────────────────────────────────────────────────────────────────────────────

class CrewGroupsScreen extends ConsumerStatefulWidget {
  const CrewGroupsScreen({super.key});

  @override
  ConsumerState<CrewGroupsScreen> createState() => _CrewGroupsScreenState();
}

class _CrewGroupsScreenState extends ConsumerState<CrewGroupsScreen> {
  List<CrewGroup>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await ref.read(squadRepositoryProvider).list();
      if (mounted) {
        setState(() {
          _groups = groups;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _start() async {
    final group = await showModalBottomSheet<CrewGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CrewInputSheet(mode: _SheetMode.create),
    );
    if (group == null || !mounted) return;
    await _load();
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
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final Widget body;
    if (groups == null && _error != null) {
      body = NuvoErrorState(message: _error!, onRetry: _load);
    } else if (groups == null) {
      body = const Center(child: NuvoLoadingIndicator());
    } else if (groups.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: NuvoEmptyState(
          icon: Icons.groups_rounded,
          title: 'Race with a crew',
          body:
              'Start a crew, share the code, and every race you bring to it '
              'lands on one leaderboard.',
          ctaLabel: 'Start a crew',
          onCta: _start,
          secondaryLabel: 'Join with a code',
          onSecondary: _join,
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            for (final g in groups) _GroupCard(group: g),
            const SizedBox(height: 8),
            NuvoPrimaryButton(
              label: 'Start a crew',
              icon: Icons.add_rounded,
              expand: true,
              onPressed: _start,
            ),
            const SizedBox(height: 10),
            NuvoOutlineButton(
              label: 'Join with a code',
              icon: Icons.login_rounded,
              expand: true,
              onPressed: _join,
            ),
          ],
        ),
      );
    }
    return NuvoPage(topBar: _topBar(context, 'Crews'), child: body);
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final CrewGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final races = '${group.raceCount} ${group.raceCount == 1 ? 'race' : 'races'}';
    final people = '${group.memberCount} in crew';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '${group.name}, $people, $races',
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/crews/${group.id}'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.panel,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        color: NuvoColors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: AppTextStyles.titleMedium
                              .copyWith(color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$people · $races',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: c.inkMuted),
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
      setState(() => _error = _isCreate
          ? 'Give your crew a name (2 characters or more).'
          : 'Enter the crew code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(squadRepositoryProvider);
    try {
      if (_isCreate) {
        final group = await repo.create(text);
        if (mounted) Navigator.of(context).pop(group);
      } else {
        await repo.join(text);
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isCreate ? 'Start a crew' : 'Join a crew',
              style: AppTextStyles.titleLarge.copyWith(color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              _isCreate
                  ? 'Name it, then share the code with your crew.'
                  : 'Enter the code your crew shared with you.',
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: _isCreate ? 40 : 12,
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
            const SizedBox(height: 16),
            NuvoPrimaryButton(
              label: _isCreate ? 'Start crew' : 'Join crew',
              expand: true,
              loading: _busy,
              onPressed: _submit,
            ),
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
  CrewGroupDetail? _detail;
  String? _error;
  String? _actionError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await ref.read(squadRepositoryProvider).detail(widget.groupId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _bringRace() async {
    final detail = _detail;
    final me = ref.read(authControllerProvider).user;
    if (detail == null || me == null) return;
    final linked = detail.races.map((r) => r.id).toSet();
    final mine = ref
        .read(raceControllerProvider)
        .races
        .where((r) =>
            r.creatorId == me.id &&
            r.status == 'active' &&
            !linked.contains(r.id))
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
              Text('Bring a race to the crew',
                  style: AppTextStyles.titleLarge.copyWith(color: c.ink)),
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
      await ref.read(squadRepositoryProvider).addRace(widget.groupId, picked);
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
      await _load();
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
      await ref.read(squadRepositoryProvider).leave(widget.groupId);
      if (mounted) _leave(context);
    } catch (e) {
      if (mounted) setState(() => _actionError = _messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final c = context.themeColors;

    if (detail == null) {
      return NuvoPage(
        topBar: _topBar(context, 'Crew'),
        child: _error != null
            ? NuvoErrorState(message: _error!, onRetry: _load)
            : const Center(child: NuvoLoadingIndicator()),
      );
    }

    return NuvoPage(
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // Leaderboard first — it is the point of the crew.
            Text('Crew leaderboard',
                style: AppTextStyles.titleLarge.copyWith(color: c.ink)),
            const SizedBox(height: 2),
            Text(
              '5 · 3 · 2 points for 1st, 2nd, 3rd in each race. 1 for any proof.',
              style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: 12),
            if (detail.races.isEmpty)
              const _InlineNote(
                icon: Icons.flag_outlined,
                text: 'No races yet. Bring a race to the crew to start '
                    'the leaderboard.',
              )
            else if (detail.standings.every((s) => s.points == 0))
              const _InlineNote(
                icon: Icons.bolt_rounded,
                text: 'No proof yet. The first proof takes the lead.',
              ),
            for (final s in detail.standings) _StandingRow(standing: s),
            const SizedBox(height: 16),
            NuvoPrimaryButton(
              label: 'Bring a race to the crew',
              icon: Icons.flag_rounded,
              expand: true,
              loading: _busy,
              onPressed: _bringRace,
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              Text(_actionError!,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: NuvoColors.danger)),
            ],
            const SizedBox(height: 24),
            _CodeCard(group: detail.group),
            if (detail.races.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Crew races',
                  style: AppTextStyles.titleLarge.copyWith(color: c.ink)),
              const SizedBox(height: 8),
              for (final r in detail.races) _RaceRow(race: r),
            ],
          ],
        ),
      ),
    );
  }
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
            child: Text(text,
                style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted)),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.group});
  final CrewGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crew code',
                    style: AppTextStyles.labelMedium.copyWith(color: c.inkMuted)),
                const SizedBox(height: 2),
                Text(
                  group.joinCode,
                  style: AppTextStyles.headlineMedium
                      .copyWith(color: c.ink, letterSpacing: 3),
                ),
                Text(
                  '${group.memberCount} in crew',
                  style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: Icon(Icons.copy_rounded, color: c.ink),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: group.joinCode));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Crew code copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Pull in your crew',
            icon: Icon(Icons.ios_share_rounded, color: c.ink),
            onPressed: () => Share.share(
              'Join my crew "${group.name}" on Nuvo. Crew code: ${group.joinCode}',
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.standing});
  final CrewGroupStanding standing;

  Color? _medal() => switch (standing.rank) {
        1 => NuvoColors.sunshine,
        2 => const Color(0xFFB8C2D6),
        3 => NuvoColors.orange,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final medal = standing.points > 0 ? _medal() : null;
    final lead = standing.points > 0 && standing.rank == 1;
    final detail = standing.races == 0
        ? 'No proof yet'
        : '${standing.races} ${standing.races == 1 ? 'race' : 'races'}'
            '${standing.wins > 0 ? ' · ${standing.wins} ${standing.wins == 1 ? 'win' : 'wins'}' : ''}';
    return Semantics(
      label: 'Rank ${standing.rank}, ${standing.displayName}, '
          '${standing.points} points',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  Text(detail,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: c.inkMuted)),
                ],
              ),
            ),
            Text('${standing.points}',
                style: AppTextStyles.titleMedium.copyWith(color: c.ink)),
            const SizedBox(width: 3),
            Text('pts',
                style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted)),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(race.title,
          style: AppTextStyles.bodyLarge.copyWith(color: c.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        live ? 'Racing now' : 'Finished',
        style: AppTextStyles.bodySmall
            .copyWith(color: live ? NuvoColors.success : c.inkMuted),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
      onTap: () => context.push('/race/${race.id}'),
    );
  }
}
