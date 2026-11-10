import '../../../core/offline/online_gate.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/demo/presentation_demo.dart';
import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/v13/v13.dart';
import '../../social/presentation/race_share_sheet.dart';
import '../data/race_models.dart';
import 'race_controller.dart';

/// `/race/:id/invite` — invite friends to a race. Search by username, add
/// from your friends, share a link/QR, or hand out the typable invite code.
class InviteCrewScreen extends ConsumerStatefulWidget {
  const InviteCrewScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<InviteCrewScreen> createState() => _InviteCrewScreenState();
}

class _InviteCrewScreenState extends ConsumerState<InviteCrewScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  Race? _race;
  List<PublicUser> _crew = const [];
  List<PublicUser> _results = const [];
  Set<String> _adding = {};
  String? _inviteCode;
  String? _error;
  String? _searchError;
  bool _loading = true;
  bool _searching = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(raceControllerProvider.notifier);
      final race = await controller.getRaceDetail(widget.raceId);
      final crew = await controller.getCrew();
      String? code = race.inviteCode;
      // Presentation-created races are local-only — no server row exists for
      // an invite code, so requesting one would 404 and flash a snackbar.
      if (code == null && !isPresentationDemoCreatedRace(widget.raceId)) {
        try {
          code = await controller.createInviteCode(widget.raceId);
        } catch (_) {
          if (mounted) {
            showV13Toast(context, "Couldn't create invite code. Try again.");
          }
        }
      }
      if (mounted) {
        setState(() {
          _race = race;
          _crew = crew;
          _inviteCode = code;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load invite details.';
          _loading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 360), () async {
      try {
        final results = await ref
            .read(raceControllerProvider.notifier)
            .searchUsers(query);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
            _searchError = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _searching = false;
            _searchError = 'We couldn’t find people right now. Try again.';
          });
        }
      }
    });
  }

  bool _isInRace(String userId) =>
      _race?.participants.any((p) => p.userId == userId) ?? false;

  Future<void> _addToRace(PublicUser user) async {
    FocusScope.of(context).unfocus();
    setState(() => _adding = {..._adding, user.id});
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .addRaceParticipant(widget.raceId, user.id, user: user);
      if (mounted) {
        setState(() {
          _race = race;
          _adding = _adding.where((id) => id != user.id).toSet();
        });
        showV13Toast(context, '${user.displayName} added to race.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _adding = _adding.where((id) => id != user.id).toSet());
        showV13Toast(context, 'Could not add this friend.');
      }
    }
  }

  Future<void> _createCode() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final code = await ref
          .read(raceControllerProvider.notifier)
          .createInviteCode(widget.raceId);
      ref.read(analyticsProvider).raceInviteSent();
      if (mounted) {
        setState(() {
          _inviteCode = code;
          _generating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not create invite code.';
          _generating = false;
        });
      }
    }
  }

  Future<void> _copyCode() async {
    final code = _inviteCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showV13Toast(context, 'Code copied.');
  }

  @override
  Widget build(BuildContext context) {
    final race = _race;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Invite your friends',
              onBack: () => safePopOrGo(context, '/race/${widget.raceId}'),
            ),
            Expanded(
              child: V13AsyncView<Race>.state(
                status: _loading
                    ? V13AsyncStatus.loading
                    : race == null
                    ? V13AsyncStatus.error
                    : V13AsyncStatus.data,
                dataValue: race,
                errorValue: _error,
                errorTitle: 'Could not load invite details',
                onRetry: _load,
                onRefresh: _load,
                builder: _body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Race race) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXxl * 2,
      ),
      children: [
        Text(race.title, style: V13.body.copyWith(color: V13.muted)),
        const SizedBox(height: V13.gapXl),
        const V13SectionHeader(title: 'Add by username'),
        const SizedBox(height: V13.gapMd),
        V13TextInput(
          controller: _searchController,
          enabled: appOnline(ref),
          hint: appOnline(ref)
              ? 'Username or member ID'
              : 'Search needs internet',
          prefixIcon: const Icon(Icons.search_rounded, color: V13.muted),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: V13.blue,
                    ),
                  ),
                )
              : null,
          onChanged: _onSearchChanged,
        ),
        if (!appOnline(ref)) const NeedsInternetLine(),
        const SizedBox(height: V13.gapMd),
        // Offline: the calm line above replaces any network error.
        if (_searchError != null && appOnline(ref))
          _InlineState(
            icon: Icons.wifi_tethering_error_rounded,
            text: _searchError!,
            actionLabel: 'Try again',
            onPressed: () => _onSearchChanged(_searchController.text),
          ),
        for (var i = 0; i < _results.length; i++)
          _InviteUserRow(
            user: _results[i],
            added: _isInRace(_results[i].id),
            loading: _adding.contains(_results[i].id),
            onAdd: () => _addToRace(_results[i]),
            onOpen: () => openPerson(context, ref, _results[i].id),
            showDivider: i < _results.length - 1,
          ),
        if (_results.isEmpty &&
            _searchController.text.trim().length >= 2 &&
            !_searching)
          Text('No matching Nuvo members found.', style: V13.caption),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Your friends'),
        const SizedBox(height: V13.gapSm),
        if (_crew.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
            child: Text(
              'Add friends in Friends, or use the invite code below.',
              style: V13.body.copyWith(color: V13.muted),
            ),
          )
        else
          for (var i = 0; i < _crew.length; i++)
            _InviteUserRow(
              user: _crew[i],
              added: _isInRace(_crew[i].id),
              loading: _adding.contains(_crew[i].id),
              onAdd: () => _addToRace(_crew[i]),
              onOpen: () => openPerson(context, ref, _crew[i].id),
              showDivider: i < _crew.length - 1,
            ),
        const SizedBox(height: V13.gapSection),
        const V13SectionHeader(title: 'Share a link or QR'),
        const SizedBox(height: V13.gapMd),
        Text(
          'Anyone with the link can preview the race and join — '
          'no code to type.',
          style: V13.body.copyWith(color: V13.muted),
        ),
        const SizedBox(height: V13.gapMd),
        V13Button.primary(
          label: 'Share link & QR',
          icon: Icons.qr_code_rounded,
          fullWidth: true,
          onPressed: () => showRaceShareSheet(
            context,
            raceId: widget.raceId,
            raceTitle: race.title,
          ),
        ),
        if (!isPresentationDemoCreatedRace(widget.raceId)) ...[
          const SizedBox(height: V13.gapSection),
          const V13SectionHeader(title: 'Or a typable code'),
          const SizedBox(height: V13.gapMd),
          _InviteCodeCard(code: _inviteCode),
          const SizedBox(height: V13.gapMd),
          if (_inviteCode == null)
            V13Button.secondary(
              label: _generating ? 'Creating…' : 'Create invite code',
              icon: Icons.key_rounded,
              fullWidth: true,
              onPressed: _generating ? null : _createCode,
            )
          else
            V13Button.secondary(
              label: 'Copy code',
              icon: Icons.copy_rounded,
              fullWidth: true,
              onPressed: _copyCode,
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: V13.gapMd),
          Text(_error!, style: V13.caption.copyWith(color: V13.danger)),
        ],
      ],
    );
  }
}

class _InviteUserRow extends StatelessWidget {
  const _InviteUserRow({
    required this.user,
    required this.added,
    required this.loading,
    required this.onAdd,
    required this.onOpen,
    required this.showDivider,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onOpen;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return V13ListRow(
      title: user.displayName,
      subtitle: user.handleLine,
      showDivider: showDivider,
      onTap: onOpen,
      leading: V13Face(
        photoUrl: user.profilePhotoUrl,
        size: 40,
        name: user.displayName,
        onTap: onOpen,
      ),
      trailing: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: V13.blue,
              ),
            )
          : added
          ? const V13Pill(label: 'Added', color: V13.mint)
          : V13Button.secondary(
              label: 'Add to race',
              size: V13ButtonSize.small,
              onPressed: onAdd,
            ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    return V13Card(
      child: Row(
        children: [
          const V13IconTile(icon: Icons.key_rounded, color: V13.sun),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Text(
              code ?? 'Create a code',
              style: code == null
                  ? V13.body.copyWith(color: V13.muted)
                  : V13.number,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: V13.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: V13.muted, size: 18),
          const SizedBox(width: V13.gapSm),
          Expanded(child: Text(text, style: V13.caption)),
          if (actionLabel != null && onPressed != null)
            V13Button.ghost(
              label: actionLabel!,
              size: V13ButtonSize.small,
              onPressed: onPressed,
            ),
        ],
      ),
    );
  }
}
