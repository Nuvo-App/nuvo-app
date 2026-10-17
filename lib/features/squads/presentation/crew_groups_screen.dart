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
import '../../../core/widgets/nuvo_page.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';
import '../data/squad_api.dart';

String _messageFor(Object e) =>
    e is ApiException ? e.message : 'Something went wrong. Try again.';

/// `/crews` — the crews I'm in, plus the two ways to get one: start a crew,
/// or join with a code. Each crew keeps its own race leaderboard.
class CrewGroupsScreen extends ConsumerStatefulWidget {
  const CrewGroupsScreen({super.key});

  @override
  ConsumerState<CrewGroupsScreen> createState() => _CrewGroupsScreenState();
}

class _CrewGroupsScreenState extends ConsumerState<CrewGroupsScreen> {
  List<CrewGroup>? _groups;
  String? _error;
  bool _busy = false;
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = await ref.read(squadRepositoryProvider).list();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
        final name = _nameController.text.trim();
        if (name.length < 2) {
          throw const ApiException(400, 'Give your crew a name.');
        }
        final group = await ref.read(squadRepositoryProvider).create(name);
        _nameController.clear();
        if (mounted) context.push('/crews/${group.id}');
        await _load();
      });

  Future<void> _join() => _run(() async {
        final code = _codeController.text.trim();
        if (code.isEmpty) throw const ApiException(400, 'Enter a crew code.');
        await ref.read(squadRepositoryProvider).join(code);
        _codeController.clear();
        await _load();
        // A crew race may have just put me in a race — refresh the lists.
        ref.read(raceControllerProvider.notifier).loadRaces(force: true);
      });

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return NuvoPage(
      topBar: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: NuvoBackHeader(title: 'Crews', onBack: () => context.pop()),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text('Race together', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Start a crew, share the code, and every race you bring to it lands on one leaderboard.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
          if (groups == null && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final g in groups ?? const <CrewGroup>[]) _GroupTile(group: g),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Crew name', counterText: ''),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 10),
          NuvoPrimaryButton(
            label: 'Start a crew',
            icon: Icons.groups_rounded,
            expand: true,
            loading: _busy,
            onPressed: _create,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Crew code'),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 10),
          NuvoOutlineButton(
            label: 'Join with code',
            icon: Icons.login_rounded,
            expand: true,
            onPressed: _busy ? null : _join,
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});
  final CrewGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/crews/${group.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: AppTextStyles.titleMedium),
                    Text(
                      '${group.memberCount} in crew · ${group.raceCount} '
                      '${group.raceCount == 1 ? 'race' : 'races'}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// `/crews/:id` — the crew leaderboard (points across every crew race), the
/// crew's races, and the one action: bring a race to the crew.
class CrewGroupDetailScreen extends ConsumerStatefulWidget {
  const CrewGroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<CrewGroupDetailScreen> createState() => _CrewGroupDetailScreenState();
}

class _CrewGroupDetailScreenState extends ConsumerState<CrewGroupDetailScreen> {
  CrewGroupDetail? _detail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await ref.read(squadRepositoryProvider).detail(widget.groupId);
      if (mounted) setState(() => _detail = detail);
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
        .where((r) => r.creatorId == me.id && r.status == 'active' && !linked.contains(r.id))
        .toList();

    if (mine.isEmpty) {
      // Nothing to bring yet — go start a race, then come back.
      context.push('/races/new');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('Bring a race to the crew', style: AppTextStyles.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Everyone in the crew is pulled in.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final race in mine)
              ListTile(
                contentPadding: EdgeInsets.zero,
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
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(squadRepositoryProvider).addRace(widget.groupId, picked);
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this crew?'),
        content: const Text('You stay in races you already joined.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(squadRepositoryProvider).leave(widget.groupId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return NuvoPage(
      topBar: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: NuvoBackHeader(
          title: detail?.group.name ?? 'Crew',
          onBack: () => context.pop(),
          trailing: detail == null
              ? null
              : IconButton(
                  tooltip: 'Leave crew',
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: _leave,
                ),
        ),
      ),
      child: detail == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  _CodeCard(group: detail.group),
                  const SizedBox(height: 16),
                  NuvoPrimaryButton(
                    label: 'Bring a race to the crew',
                    icon: Icons.flag_rounded,
                    expand: true,
                    loading: _busy,
                    onPressed: _bringRace,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 24),
                  Text('Crew leaderboard', style: AppTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '5 / 3 / 2 points for 1st / 2nd / 3rd in each race, 1 for any proof.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  for (final s in detail.standings) _StandingRow(standing: s),
                  if (detail.races.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Crew races', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 8),
                    for (final r in detail.races)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.title),
                        subtitle: Text(r.status == 'active' ? 'Racing' : 'Finished'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/race/${r.id}'),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.group});
  final CrewGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crew code', style: AppTextStyles.labelMedium),
                const SizedBox(height: 2),
                Text(
                  group.joinCode,
                  style: AppTextStyles.headlineMedium.copyWith(letterSpacing: 3),
                ),
                Text(
                  '${group.memberCount} in crew',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: group.joinCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Crew code copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Pull in your crew',
            icon: const Icon(Icons.ios_share_rounded),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: standing.isYou ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: standing.isYou ? 1.5 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${standing.rank}', style: AppTextStyles.titleMedium),
          ),
          NuvoAvatar(
            initials: standing.initials,
            size: NuvoAvatarSizes.sm,
            photoUrl: standing.profilePhotoUrl,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              standing.isYou ? '${standing.displayName} (you)' : standing.displayName,
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${standing.points} pts', style: AppTextStyles.titleMedium),
        ],
      ),
    );
  }
}
