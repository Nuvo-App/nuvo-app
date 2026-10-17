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
    // A swipe-down dismiss leaves the text field's focus (and the keyboard)
    // behind — drop it whichever way the sheet closed.
    FocusManager.instance.primaryFocus?.unfocus();
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
    FocusManager.instance.primaryFocus?.unfocus();
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
        color: c.surface,
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
                        color: c.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border, width: 1.5),
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
    FocusManager.instance.primaryFocus?.unfocus();
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
    final router = GoRouter.maybeOf(context);
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
                    color: c.surface,
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
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
                  router?.push('/scan');
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
  int _tab = 0;

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

  Future<void> _addPeople() async {
    final detail = ref.read(squadControllerProvider).details[widget.groupId];
    if (detail == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kSide, 0, _kSide, _kSide),
          child: SingleChildScrollView(child: _CodeCard(group: detail.group)),
        ),
      ),
    );
  }

  Future<void> _manageMember(CrewMember member) async {
    final detail = ref.read(squadControllerProvider).details[widget.groupId];
    if (detail == null) return;
    final iAmOwner = detail.group.isOwner;
    final canRemove =
        !member.isOwner &&
        (iAmOwner || (!member.isAdmin && detail.group.canManage));
    final canSetRole = iAmOwner && !member.isOwner;
    if (!canRemove && !canSetRole) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kSide, 0, _kSide, _kSide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName,
                style: AppTextStyles.titleLarge.copyWith(
                  color: ctx.themeColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (canSetRole)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    member.isAdmin
                        ? Icons.remove_moderator_outlined
                        : Icons.admin_panel_settings_outlined,
                  ),
                  title: Text(member.isAdmin ? 'Remove admin' : 'Make admin'),
                  subtitle: Text(
                    member.isAdmin
                        ? 'They go back to a regular member.'
                        : 'Admins can add races and remove members.',
                  ),
                  onTap: () => Navigator.of(ctx).pop('role'),
                ),
              if (canRemove)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: ctx.dangerInk,
                  ),
                  title: Text(
                    'Remove from crew',
                    style: TextStyle(color: ctx.dangerInk),
                  ),
                  onTap: () => Navigator.of(ctx).pop('remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    final squads = ref.read(squadControllerProvider.notifier);
    if (action == 'remove') {
      final ok = await showNuvoConfirmDialog(
        context,
        title: 'Remove ${member.displayName}?',
        message: 'They leave this crew and can\'t rejoin with the code.',
        confirmLabel: 'Remove',
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      if (action == 'role') {
        await squads.setRole(
          widget.groupId,
          member.userId,
          member.isAdmin ? 'member' : 'admin',
        );
      } else {
        await squads.removeMember(widget.groupId, member.userId);
      }
    } catch (e) {
      if (mounted) setState(() => _actionError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeRace(CrewGroupRace race) async {
    final ok = await showNuvoConfirmDialog(
      context,
      title: 'Remove "${race.title}"?',
      message:
          'It stops counting for the crew leaderboard. Everyone stays in the race.',
      confirmLabel: 'Remove',
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await ref
          .read(squadControllerProvider.notifier)
          .removeRace(widget.groupId, race.id);
    } catch (e) {
      if (mounted) setState(() => _actionError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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

    final group = detail.group;
    final canManage = group.canManage;
    final alone = detail.members.length <= 1 && group.memberCount <= 1;

    // Races first (each opens its own leaderboard), then the people.
    final Widget content = switch (_tab) {
      1 => _MembersTab(
        detail: detail,
        onAdd: _addPeople,
        onManage: _manageMember,
      ),
      _ => _RacesTab(
        detail: detail,
        canManage: canManage,
        busy: _busy,
        alone: alone,
        onAdd: _bringRace,
        onRemove: _removeRace,
      ),
    };

    return LiveRefresh(
      onRefresh: () => ref
          .read(squadControllerProvider.notifier)
          .refreshDetail(widget.groupId),
      child: NuvoPage(
        topBar: _topBar(
          context,
          group.name,
          trailing: IconButton(
            key: const ValueKey('crew-settings-button'),
            tooltip: 'Crew settings',
            icon: Icon(Icons.settings_outlined, color: c.ink),
            onPressed: () => context.push('/crews/${widget.groupId}/settings'),
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
                _CrewSummaryCard(
                  detail: detail,
                  onAddPeople: _addPeople,
                  onAddRace: canManage ? _bringRace : null,
                  busy: _busy,
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
                _CrewTabBar(
                  selected: _tab,
                  labels: [
                    'Races ${group.raceCount}',
                    'Members ${group.memberCount}',
                  ],
                  onSelect: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: NuvoSpacing.lg),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// The crew at a glance: how big it is, my role, and the two things an owner
/// does most — pull people in and bring races.
class _CrewSummaryCard extends StatelessWidget {
  const _CrewSummaryCard({
    required this.detail,
    required this.onAddPeople,
    required this.onAddRace,
    required this.busy,
  });

  final CrewGroupDetail detail;
  final VoidCallback onAddPeople;
  final VoidCallback? onAddRace;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final g = detail.group;
    final role = g.isOwner
        ? 'Owner'
        : (g.myRole == 'admin' ? 'Admin' : 'Member');
    return Container(
      key: const ValueKey('crew-summary'),
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
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border, width: 1.5),
                ),
                alignment: Alignment.center,
                child: const NuvoCrewIcon(size: 28, semanticLabel: null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                    ),
                    Text(
                      '${g.memberCount} ${g.memberCount == 1 ? 'member' : 'members'}'
                      ' · ${g.raceCount} ${g.raceCount == 1 ? 'race' : 'races'}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _RoleChip(
                label: role,
                role: g.isOwner ? 'owner' : (g.myRole == 'admin' ? 'admin' : 'member'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final stacked =
                  MediaQuery.sizeOf(context).width < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.15;
              final addPeople = NuvoPrimaryButton(
                label: 'Add people',
                icon: Icons.qr_code_2_rounded,
                expand: true,
                onPressed: onAddPeople,
              );
              final addRace = onAddRace == null
                  ? null
                  : NuvoOutlineButton(
                      label: 'Add race',
                      icon: Icons.flag_rounded,
                      expand: true,
                      onPressed: busy ? null : onAddRace,
                    );
              if (addRace == null) return addPeople;
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [addPeople, const SizedBox(height: 8), addRace],
                    )
                  : Row(
                      children: [
                        Expanded(child: addPeople),
                        const SizedBox(width: 10),
                        Expanded(child: addRace),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, this.role = 'member'});
  final String label;
  final String role;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    // Solid colour is the highlight: owner = gold, admin = Nuvo blue.
    final (fill, text, edge) = switch (role) {
      'owner' => (NuvoColors.gold, NuvoColors.navy, NuvoColors.gold),
      'admin' => (NuvoColors.blue, NuvoColors.white, NuvoColors.blue),
      _ => (c.surface, c.inkMuted, c.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: edge),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppTextStyles.labelMedium.copyWith(
          color: text,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Three views of one crew: standings, people, races.
class _CrewTabBar extends StatelessWidget {
  const _CrewTabBar({
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      key: const ValueKey('crew-tabs'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: c.border, width: 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: labels[i],
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == selected ? NuvoColors.blue : Colors.transparent,
                      borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: i == selected ? NuvoColors.white : c.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.detail,
    required this.onAdd,
    required this.onManage,
  });

  final CrewGroupDetail detail;
  final VoidCallback onAdd;
  final ValueChanged<CrewMember> onManage;

  static int _order(CrewMember m) => m.isOwner ? 0 : (m.isAdmin ? 1 : 2);

  @override
  Widget build(BuildContext context) {
    final g = detail.group;
    final members = [...detail.members]
      ..sort((a, b) => _order(a).compareTo(_order(b)));
    if (members.isEmpty) {
      return const _InlineNote(
        icon: Icons.groups_outlined,
        text: 'Members will show up here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in members)
          _MemberRow(
            member: m,
            canManage: !m.isOwner && (g.isOwner || (g.canManage && !m.isAdmin)),
            onManage: () => onManage(m),
          ),
        const SizedBox(height: NuvoSpacing.xs),
        NuvoOutlineButton(
          label: 'Add people',
          icon: Icons.qr_code_2_rounded,
          expand: true,
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canManage,
    required this.onManage,
  });

  final CrewMember member;
  final bool canManage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border, width: 2),
      ),
      child: Row(
        children: [
          NuvoAvatar(
            initials: member.initials,
            size: NuvoAvatarSizes.sm,
            photoUrl: member.profilePhotoUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
                ),
                if (member.username != null)
                  Text(
                    '@${member.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                  ),
              ],
            ),
          ),
          if (member.isOwner || member.isAdmin) ...[
            _RoleChip(
              label: member.isOwner ? 'Owner' : 'Admin',
              role: member.isOwner ? 'owner' : 'admin',
            ),
            const SizedBox(width: 4),
          ],
          if (canManage)
            IconButton(
              tooltip: 'Manage ${member.displayName}',
              icon: Icon(Icons.more_horiz_rounded, color: c.ink),
              onPressed: onManage,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _RacesTab extends StatelessWidget {
  const _RacesTab({
    required this.detail,
    required this.canManage,
    required this.busy,
    required this.alone,
    required this.onAdd,
    required this.onRemove,
  });

  final CrewGroupDetail detail;
  final bool canManage;
  final bool busy;
  final bool alone;
  final VoidCallback onAdd;
  final ValueChanged<CrewGroupRace> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final live = detail.races.where((r) => r.status == 'active').toList();
    final done = detail.races.where((r) => r.status != 'active').toList();
    Widget section(String title, List<CrewGroupRace> races) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(color: c.ink),
          ),
        ),
        // One card per race: every race is its own bordered block, so the
        // list reads as separate items and simply keeps going as it grows.
        for (final r in races)
          _RaceRow(
            race: r,
            onRemove: canManage ? () => onRemove(r) : null,
          ),
        const SizedBox(height: NuvoSpacing.md),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (alone) ...[
          // Nobody else yet: the next move is getting people in.
          _CodeCard(group: detail.group, title: 'Just you so far'),
          const SizedBox(height: NuvoSpacing.lg),
        ],
        if (detail.races.isEmpty) ...[
          const _InlineNote(
            icon: Icons.flag_outlined,
            text: 'No races yet. Races you add count for the whole crew.',
          ),
          if (canManage)
            NuvoPrimaryButton(
              label: 'Add a race',
              icon: Icons.flag_rounded,
              expand: true,
              loading: busy,
              onPressed: onAdd,
            )
          else
            Text(
              'Crew admins add races.',
              style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
            ),
        ] else ...[
          Text(
            'Tap a race to see its leaderboard.',
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: NuvoSpacing.md),
          if (live.isNotEmpty) section('Racing now', live),
          if (done.isNotEmpty) section('Finished', done),
        ],
      ],
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
  const _CodeCard({required this.group, this.title = 'Pull in your crew'});
  final CrewGroup group;
  final String title;

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
          Text(title, style: AppTextStyles.titleMedium.copyWith(color: c.ink)),
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

class _RaceRow extends StatelessWidget {
  const _RaceRow({required this.race, this.onRemove});
  final CrewGroupRace race;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final sem = context.semanticColors;
    final live = race.status == 'active';
    // Green = running now; gold = finished. The border carries the colour.
    final tone = live ? sem.success : sem.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 3),
      child: Semantics(
        button: true,
        label: '${race.title}, ${live ? 'racing now' : 'finished'}. Open leaderboard.',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            boxShadow: tone.hardShadow(offset: const Offset(3, 3)),
          ),
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(NuvoRadii.lg),
              onTap: () => context.push('/race/${race.id}'),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NuvoRadii.lg),
                  border: Border.all(color: tone.base, width: 2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            race.title,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: c.ink,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: tone.base,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  live ? 'Racing now' : 'Finished',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: tone.on,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Remove ${race.title} from crew',
                        icon: Icon(Icons.more_horiz_rounded, color: c.ink),
                        onPressed: onRemove,
                      )
                    else
                      Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
                    if (onRemove != null)
                      Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
                    const SizedBox(width: 6),
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
// /crews/:id/settings — rename, code, about, leave
// ─────────────────────────────────────────────────────────────────────────────

class CrewSettingsScreen extends ConsumerStatefulWidget {
  const CrewSettingsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<CrewSettingsScreen> createState() => _CrewSettingsScreenState();
}

class _CrewSettingsScreenState extends ConsumerState<CrewSettingsScreen> {
  final _name = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _leaving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    Future(() {
      if (!mounted) return;
      ref.read(squadControllerProvider.notifier).loadDetail(widget.groupId);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(CrewGroup g) async {
    final next = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (next.length < 2) {
      setState(() => _error = 'Give your crew a name (2 characters or more).');
      return;
    }
    if (next == g.name) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    try {
      await ref.read(squadControllerProvider.notifier).rename(g.id, next);
      if (mounted) setState(() => _saved = 'Name updated.');
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leaveCrew(CrewGroup g) async {
    final ok = await showNuvoConfirmDialog(
      context,
      title: 'Leave ${g.name}?',
      message: g.isOwner
          ? 'You stay in races you already joined. Ownership passes to an '
                'admin, or to the longest-standing member.'
          : 'You stay in races you already joined.',
      confirmLabel: 'Leave crew',
    );
    if (ok != true || !mounted) return;
    setState(() {
      _leaving = true;
      _error = null;
    });
    try {
      await ref.read(squadControllerProvider.notifier).leave(g.id);
      if (mounted) context.go('/crews');
    } catch (e) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _error = _messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final squads = ref.watch(squadControllerProvider);
    final detail = squads.details[widget.groupId];
    final c = context.themeColors;
    final sem = context.semanticColors;
    if (detail == null) {
      final error = squads.detailErrors[widget.groupId];
      return NuvoPage(
        topBar: _topBar(context, 'Crew settings'),
        child: error != null
            ? NuvoErrorState(
                message: error,
                onRetry: () => ref
                    .read(squadControllerProvider.notifier)
                    .refreshDetail(widget.groupId),
              )
            : const Center(child: NuvoLoadingIndicator()),
      );
    }
    final g = detail.group;
    if (!_seeded) {
      _name.text = g.name;
      _seeded = true;
    }
    final role = g.isOwner ? 'Owner' : (g.myRole == 'admin' ? 'Admin' : 'Member');
    return NuvoPage(
      topBar: _topBar(context, 'Crew settings'),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          _kSide,
          NuvoSpacing.md,
          _kSide,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          _SettingsSection(
            title: 'Name',
            tone: sem.neutral,
            child: g.canManage
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('crew-rename'),
                        controller: _name,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(g),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: InputDecoration(
                          labelText: 'Crew name',
                          counterText: '',
                          errorText: _error,
                        ),
                      ),
                      if (_saved != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _saved!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: c.successText,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      NuvoPrimaryButton(
                        label: 'Save name',
                        expand: true,
                        loading: _saving,
                        onPressed: () => _save(g),
                      ),
                    ],
                  )
                : Text(
                    g.name,
                    style: AppTextStyles.titleMedium.copyWith(color: c.ink),
                  ),
          ),
          const SizedBox(height: NuvoSpacing.lg),
          _SettingsSection(
            title: 'Crew code',
            tone: sem.accent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    g.joinCode,
                    style: AppTextStyles.titleLarge.copyWith(
                      color: c.ink,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  icon: Icon(Icons.copy_rounded, color: c.ink),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: g.joinCode));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Crew code copied')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: Icon(Icons.ios_share_rounded, color: c.ink),
                  onPressed: () => Share.share(
                    'Join my crew "${g.name}" on Nuvo. Crew code: ${g.joinCode}'
                    '\nhttps://getnuvo.net/c/${g.joinCode}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NuvoSpacing.lg),
          _SettingsSection(
            title: 'About',
            tone: sem.success,
            child: Column(
              children: [
                _InfoRow(label: 'Members', value: '${g.memberCount}'),
                _InfoRow(label: 'Races', value: '${g.raceCount}'),
                _InfoRow(label: 'Your role', value: role),
              ],
            ),
          ),
          const SizedBox(height: NuvoSpacing.lg),
          _SettingsSection(
            title: 'Leave',
            tone: sem.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  g.isOwner
                      ? 'You own this crew. If you leave, ownership passes to '
                            'an admin, or to the longest-standing member.'
                      : 'You will leave the crew and its leaderboard. You stay '
                            'in races you already joined.',
                  style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: 12),
                NuvoDangerButton(
                  label: 'Leave crew',
                  icon: Icons.logout_rounded,
                  expand: true,
                  loading: _leaving,
                  onPressed: () => _leaveCrew(g),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings group: a coloured label dot + title over an outlined card.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.tone,
    required this.child,
  });

  final String title;
  final NuvoColorRole tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tone.base,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.titleMedium.copyWith(color: c.ink),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(color: tone.border, width: 2),
            boxShadow: tone.hardShadow(),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
