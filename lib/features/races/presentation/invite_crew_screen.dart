import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../data/race_models.dart';
import 'race_controller.dart';

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
      if (code == null) {
        try {
          code = await controller.createInviteCode(widget.raceId);
        } catch (_) {}
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
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await ref
            .read(raceControllerProvider.notifier)
            .searchUsers(query);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  bool _isInRace(String userId) =>
      _race?.participants.any((p) => p.userId == userId) ?? false;

  Future<void> _addToRace(PublicUser user) async {
    setState(() => _adding = {..._adding, user.id});
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .addRaceParticipant(widget.raceId, user.id);
      if (mounted) {
        setState(() {
          _race = race;
          _adding = _adding.where((id) => id != user.id).toSet();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.displayName} added to race.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _adding = _adding.where((id) => id != user.id).toSet());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add this crew member.')),
        );
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

  String get _shareText =>
      'Join my Nuvo race: ${_race?.title ?? 'Nuvo race'}\nOpen Nuvo and enter code: ${_inviteCode ?? ''}';

  Future<void> _copyCode() async {
    final code = _inviteCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: NuvoErrorState(
            message: _error ?? 'Invite details could not load.',
            onRetry: _load,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child:
            ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    NuvoBackButton(
                      onPressed: () =>
                          safePopOrGo(context, '/race/${widget.raceId}'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Pull in your crew',
                      style: AppTextStyles.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _race!.title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Add by username', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 10),
                    _SearchField(
                      controller: _searchController,
                      searching: _searching,
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: 12),
                    for (final user in _results)
                      _InviteUserRow(
                        user: user,
                        added: _isInRace(user.id),
                        loading: _adding.contains(user.id),
                        onPressed: () => _addToRace(user),
                      ),
                    if (_results.isEmpty &&
                        _searchController.text.trim().length >= 2 &&
                        !_searching)
                      const _SmallPanel(
                        text: 'No matching Nuvo members found.',
                      ),
                    const SizedBox(height: 24),
                    Text('Your crew', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 10),
                    if (_crew.isEmpty)
                      const _SmallPanel(
                        text:
                            'Add people in Crew, or use the invite code below.',
                      )
                    else
                      for (final user in _crew)
                        _InviteUserRow(
                          user: user,
                          added: _isInRace(user.id),
                          loading: _adding.contains(user.id),
                          onPressed: () => _addToRace(user),
                        ),
                    const SizedBox(height: 24),
                    Text('Invite code', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 10),
                    _InviteCodeCard(code: _inviteCode),
                    const SizedBox(height: 14),
                    if (_inviteCode == null)
                      NuvoPrimaryButton(
                        label: 'Create invite code',
                        icon: Icons.key_rounded,
                        expand: true,
                        loading: _generating,
                        onPressed: _generating ? null : _createCode,
                      )
                    else ...[
                      NuvoPrimaryButton(
                        label: 'Copy code',
                        icon: Icons.copy_rounded,
                        expand: true,
                        onPressed: _copyCode,
                      ),
                      const SizedBox(height: 12),
                      NuvoOutlineButton(
                        label: 'Share race',
                        icon: Icons.ios_share_rounded,
                        expand: true,
                        onPressed: () => Share.share(_shareText),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.danger,
                        ),
                      ),
                    ],
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.searching,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool searching;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1007152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: NuvoColors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search username or member ID',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (searching)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteUserRow extends StatelessWidget {
  const _InviteUserRow({
    required this.user,
    required this.added,
    required this.loading,
    required this.onPressed,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NuvoCompactCard(
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: NuvoColors.navy,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                user.initials,
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    user.handleLine,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 112,
              child: NuvoOutlineButton(
                label: loading
                    ? '...'
                    : added
                    ? 'Added'
                    : 'Add to race',
                small: true,
                onPressed: added || loading ? null : onPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3307152B),
            blurRadius: 0,
            offset: Offset(5, 6),
          ),
        ],
      ),
      child: Text(
        code ?? 'Create a code',
        style: AppTextStyles.headlineLarge.copyWith(color: NuvoColors.white),
      ),
    );
  }
}

class _SmallPanel extends StatelessWidget {
  const _SmallPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return NuvoCompactCard(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}
