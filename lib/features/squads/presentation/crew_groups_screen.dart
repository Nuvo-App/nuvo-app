import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/live_refresh.dart';
import 'package:nuvo/features/auth/data/auth_api.dart' show ApiException;
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/presentation/v13/crew_tab_v13_widgets.dart';

import '../application/squad_controller.dart';
import '../data/squad_api.dart';

String _messageFor(Object e) =>
    e is ApiException ? e.message : 'Something went wrong. Try again.';

/// The one invite text used by every Share button.
String _inviteText(CrewGroup g) =>
    'Join my crew "${g.name}" on Nuvo. Crew code: ${g.joinCode}'
    '\nhttps://getnuvo.net/c/${g.joinCode}';

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
    CrewGroup? created;
    final done = await showV13Sheet<bool>(
      context,
      builder: (_) => CrewInputSheet(
        title: 'Start a crew',
        hint: 'Crew name',
        buttonLabel: 'Create crew',
        onSubmit: (name) async {
          if (name.trim().length < 2) {
            return 'Give your crew a name (2 characters or more).';
          }
          try {
            created = await ref
                .read(squadControllerProvider.notifier)
                .create(name.trim());
            return null;
          } on ApiException catch (e) {
            return e.statusCode >= 500
                ? "Couldn't start the crew. Try again."
                : e.message;
          } catch (_) {
            return "Couldn't start the crew. Try again.";
          }
        },
      ),
    );
    // A swipe-down dismiss leaves the text field's focus (and the keyboard)
    // behind — drop it whichever way the sheet closed.
    FocusManager.instance.primaryFocus?.unfocus();
    final group = created;
    if (done == true && mounted && group != null) {
      showV13Toast(context, 'Your crew is live.');
      context.push('/crews/${group.id}');
    }
  }

  Future<void> _join() async {
    final done = await showV13Sheet<bool>(
      context,
      builder: (_) => CrewInputSheet(
        title: 'Join with a code',
        hint: 'Crew code',
        buttonLabel: 'Join crew',
        upperCase: true,
        onSubmit: (code) async {
          if (code.isEmpty) return 'Enter the crew code.';
          try {
            await ref.read(squadControllerProvider.notifier).join(code);
            return null;
          } on ApiException catch (e) {
            return e.statusCode >= 500
                ? "Couldn't join. Try again."
                : e.message;
          } catch (_) {
            return "That code didn't work. Check it and try again.";
          }
        },
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (done == true && mounted) {
      showV13Confetti(context);
      showV13Toast(context, "You're in the crew.");
      // Joining pulls me into the crew's running races — refresh race lists.
      ref.read(raceControllerProvider.notifier).loadRaces(force: true);
    }
  }

  void _scan() => openScan(context);

  @override
  Widget build(BuildContext context) {
    final squads = ref.watch(squadControllerProvider);
    final groups = squads.groups;
    final error = squads.error;
    return LiveRefresh(
      onRefresh: () => ref.read(squadControllerProvider.notifier).refresh(),
      child: Scaffold(
        backgroundColor: V13.bg,
        body: SafeArea(
          child: Column(
            children: [
              const V13BackBar(title: 'Crews', fallback: '/pass'),
              Expanded(child: _body(groups, error)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<CrewGroup>? groups, String? error) {
    if (groups == null) {
      if (error != null) {
        return V13AsyncView<Never>.state(
          status: V13AsyncStatus.error,
          errorTitle: "Couldn't load your crews",
          errorBody: error,
          onRetry: _load,
          onRefresh: _load,
          builder: (_) => const SizedBox.shrink(),
        );
      }
      return const V13Skeleton.screen();
    }
    return V13AsyncView<List<CrewGroup>>.state(
      status: groups.isEmpty ? V13AsyncStatus.empty : V13AsyncStatus.data,
      dataValue: groups,
      emptyIcon: Icons.groups_rounded,
      emptyTitle: 'Race with a crew',
      emptyBody:
          'Start a crew, share the code, and every race you '
          'bring to it lands on one leaderboard.',
      emptyAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          V13Button.primary(
            label: 'Start a crew',
            icon: Icons.add_rounded,
            fullWidth: true,
            onPressed: _start,
          ),
          const SizedBox(height: V13.gapMd),
          V13Button.secondary(
            label: 'Join with a code',
            icon: Icons.login_rounded,
            fullWidth: true,
            onPressed: _join,
          ),
        ],
      ),
      onRefresh: _load,
      builder: (list) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          V13.pagePad,
          V13.gapMd,
          V13.pagePad,
          V13.gapXxl,
        ),
        children: [
          for (final g in list) ...[
            CrewGroupCard(crew: g, onTap: () => context.push('/crews/${g.id}')),
            const SizedBox(height: V13.gapMd),
          ],
          V13Card.dashed(
            onTap: _start,
            semanticLabel: 'Start a crew',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, color: V13.navy),
                const SizedBox(width: V13.gapSm),
                Flexible(
                  child: Text(
                    'Start a crew',
                    style: V13.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          V13ListRow(
            leading: const V13IconTile(
              icon: Icons.key_rounded,
              color: V13.sky,
              size: 40,
            ),
            title: 'Join with a code',
            subtitle: 'Got a crew code from a friend?',
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: _join,
          ),
          V13ListRow(
            leading: const V13IconTile(
              icon: Icons.qr_code_scanner_rounded,
              color: V13.mint,
              size: 40,
            ),
            title: 'Scan a crew QR',
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: _scan,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// /crews/join/:code — confirm before joining
// ─────────────────────────────────────────────────────────────────────────────

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
      showV13Confetti(context);
      showV13Toast(context, "You're in the crew.");
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
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'Join a crew', fallback: '/pass'),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.all(V13.pagePad),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - V13.pagePad * 2,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const V13IconTile(
                          icon: Icons.groups_rounded,
                          color: V13.sky,
                          size: 76,
                          radius: V13.radiusTileLg,
                        ),
                        const SizedBox(height: V13.gapLg),
                        Text(
                          'Join this crew?',
                          textAlign: TextAlign.center,
                          style: V13.sectionHead,
                        ),
                        const SizedBox(height: V13.gapSm),
                        Text(
                          widget.code,
                          style: V13.sectionHead.copyWith(letterSpacing: 4),
                        ),
                        const SizedBox(height: V13.gapSm),
                        Text(
                          'You will join its leaderboard and its running races.',
                          textAlign: TextAlign.center,
                          style: V13.body.copyWith(color: V13.muted),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: V13.gapMd),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: V13.caption.copyWith(color: V13.danger),
                          ),
                        ],
                        const SizedBox(height: V13.gapXl),
                        V13Button.primary(
                          label: 'Join crew',
                          fullWidth: true,
                          loading: _busy,
                          onPressed: _join,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// /crews/:id/settings — rename, code, about, leave, delete
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
  bool _deleting = false;
  String? _error;

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
    });
    try {
      await ref.read(squadControllerProvider.notifier).rename(g.id, next);
      if (mounted) showV13Toast(context, 'Name updated.');
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyCode(CrewGroup g) async {
    await Clipboard.setData(ClipboardData(text: g.joinCode));
    V13Haptics.select();
    if (mounted) showV13Toast(context, 'Crew code copied');
  }

  Future<void> _shareCrew(CrewGroup g) async {
    final text = _inviteText(g);
    Rect? origin;
    try {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.width > 0 && rect.height > 0) origin = rect;
      }
    } catch (_) {
      origin = null;
    }
    var copied = false;
    try {
      final result = await Share.share(
        text,
        subject: g.name,
        sharePositionOrigin: origin,
      );
      copied = result.status == ShareResultStatus.unavailable;
    } catch (_) {
      copied = true;
    }
    if (!copied || !mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showV13Toast(context, 'Invite copied — paste it into a message');
    }
  }

  Future<void> _leaveCrew(CrewGroup g) async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Leave ${g.name}?',
      body: g.isOwner
          ? 'You stay in races you already joined. Ownership passes to an '
                'admin, or to the longest-standing member.'
          : 'You stay in races you already joined.',
      confirmLabel: 'Leave crew',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _leaving = true;
      _error = null;
    });
    try {
      await ref.read(squadControllerProvider.notifier).leave(g.id);
      if (!mounted) return;
      showV13Toast(context, 'You left ${g.name}.');
      context.go('/crews');
    } catch (e) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _error = _messageFor(e);
        });
      }
    }
  }

  Future<void> _deleteCrew(CrewGroup g) async {
    final ok = await showV13ConfirmSheet(
      context,
      title: 'Delete ${g.name}?',
      body:
          'This removes the crew for everyone: the leaderboard, members and '
          'crew code stop working. Races stay as they are.',
      confirmLabel: 'Delete crew',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(squadControllerProvider.notifier).deleteCrew(g.id);
      if (!mounted) return;
      showV13Toast(context, '${g.name} deleted.');
      context.go('/crews');
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = _messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final squads = ref.watch(squadControllerProvider);
    final detail = squads.details[widget.groupId];
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'Crew settings', fallback: '/pass'),
            Expanded(child: _body(squads, detail)),
          ],
        ),
      ),
    );
  }

  Widget _body(SquadState squads, CrewGroupDetail? detail) {
    if (detail == null) {
      final error = squads.detailErrors[widget.groupId];
      if (error != null) {
        return V13AsyncView<Never>.state(
          status: V13AsyncStatus.error,
          errorTitle: "Couldn't load crew settings",
          errorBody: error,
          onRetry: () => ref
              .read(squadControllerProvider.notifier)
              .refreshDetail(widget.groupId),
          builder: (_) => const SizedBox.shrink(),
        );
      }
      return const V13Skeleton.screen();
    }
    final g = detail.group;
    if (!_seeded) {
      _name.text = g.name;
      _seeded = true;
    }
    final role = g.isOwner
        ? 'Owner'
        : (g.myRole == 'admin' ? 'Admin' : 'Member');
    return ListView(
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXxl + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        const V13SectionHeader(title: 'Name'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          child: g.canManage
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    V13TextInput(
                      key: const ValueKey('crew-rename'),
                      controller: _name,
                      label: 'Crew name',
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [LengthLimitingTextInputFormatter(40)],
                      errorText: _error,
                      onSubmitted: (_) => _save(g),
                    ),
                    const SizedBox(height: V13.gapMd),
                    V13Button.primary(
                      label: 'Save name',
                      fullWidth: true,
                      loading: _saving,
                      onPressed: () => _save(g),
                    ),
                  ],
                )
              : Text(g.name, style: V13.bodyStrong),
        ),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Crew code'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  g.joinCode,
                  style: V13.sectionHead.copyWith(letterSpacing: 4),
                ),
              ),
              V13IconButton(
                icon: Icons.copy_rounded,
                semanticLabel: 'Copy code',
                onTap: () => _copyCode(g),
              ),
              const SizedBox(width: V13.gapSm),
              V13IconButton(
                icon: Icons.ios_share_rounded,
                semanticLabel: 'Share crew invite',
                onTap: () => _shareCrew(g),
              ),
            ],
          ),
        ),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'About'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
          child: Column(
            children: [
              _InfoRow(label: 'Members', value: '${g.memberCount}'),
              const V13Divider(),
              _InfoRow(label: 'Races', value: '${g.raceCount}'),
              const V13Divider(),
              _InfoRow(label: 'Your role', value: role),
            ],
          ),
        ),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Leave'),
        const SizedBox(height: V13.gapMd),
        V13Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                g.isOwner
                    ? 'You own this crew. If you leave, ownership passes to '
                          'an admin, or to the longest-standing member.'
                    : 'You will leave the crew and its leaderboard. You stay '
                          'in races you already joined.',
                style: V13.caption,
              ),
              const SizedBox(height: V13.gapMd),
              V13Button.danger(
                label: 'Leave crew',
                icon: Icons.logout_rounded,
                fullWidth: true,
                loading: _leaving,
                onPressed: () => _leaveCrew(g),
              ),
            ],
          ),
        ),
        if (g.isOwner) ...[
          const SizedBox(height: V13.gapSection),
          const V13SectionHeader(title: 'Delete'),
          const SizedBox(height: V13.gapMd),
          V13Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Delete removes this crew for everyone. The leaderboard, '
                  'members and crew code stop working. Races stay as they '
                  'are.',
                  style: V13.caption,
                ),
                const SizedBox(height: V13.gapMd),
                V13Button.danger(
                  key: const ValueKey('crew-delete'),
                  label: 'Delete crew',
                  icon: Icons.delete_outline_rounded,
                  fullWidth: true,
                  loading: _deleting,
                  onPressed: (_leaving || _deleting)
                      ? null
                      : () => _deleteCrew(g),
                ),
              ],
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
      child: Row(
        children: [
          Expanded(child: Text(label, style: V13.body)),
          Text(value, style: V13.bodyStrong),
        ],
      ),
    );
  }
}
