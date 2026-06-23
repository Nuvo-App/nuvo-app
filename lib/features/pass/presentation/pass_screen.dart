import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

class PassScreen extends ConsumerStatefulWidget {
  const PassScreen({super.key});

  @override
  ConsumerState<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends ConsumerState<PassScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  PassInfo? _passInfo;
  List<PublicUser> _crew = const [];
  List<PublicUser> _results = const [];
  Set<String> _adding = {};
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final passFuture = ref.read(authControllerProvider.notifier).getMemberPass();
      final crewFuture = ref.read(raceControllerProvider.notifier).getCrew();
      final pass = await passFuture;
      final crew = await crewFuture;
      if (mounted) {
        setState(() {
          _passInfo = pass;
          _crew = crew;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your crew.';
          _loading = false;
        });
      }
    }
  }

  UserProfile _buildProfile(AuthUser? user) {
    return UserProfile(
      name: user?.fullName ?? user?.email ?? '',
      username: user?.username ?? '',
      memberId: _passInfo?.memberId ?? '-',
      passSlug: _passInfo?.passSlug,
    );
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
        final results =
            await ref.read(raceControllerProvider.notifier).searchUsers(query);
        if (mounted) setState(() { _results = results; _searching = false; });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _addCrew(PublicUser user) async {
    setState(() => _adding = {..._adding, user.id});
    try {
      await ref.read(raceControllerProvider.notifier).addCrewUser(user.id);
      final crew = await ref.read(raceControllerProvider.notifier).getCrew();
      if (mounted) {
        setState(() {
          _crew = crew;
          _adding = _adding.where((id) => id != user.id).toSet();
        });
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

  bool _isCrew(PublicUser user) => _crew.any((m) => m.id == user.id);

  void _sharePass() {
    final passInfo = _passInfo;
    if (passInfo == null) return;
    Share.share(passInfo.shareUrl);
  }

  Future<void> _copyId() async {
    final passInfo = _passInfo;
    if (passInfo == null) return;
    await Clipboard.setData(ClipboardData(text: passInfo.memberId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member ID copied.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = _buildProfile(user);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            children: [
              // ── Header ───────────────────────────────────────────────────
              Text(
                'CREW',
                style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
              ),
              const SizedBox(height: 2),
              Text('Your crew.', style: AppTextStyles.displaySmall),
              const SizedBox(height: 28),

              // ── Loading ──────────────────────────────────────────────────
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              // ── Error ────────────────────────────────────────────────────
              else if (_error != null)
                NuvoErrorState(message: _error!, onRetry: _fetch)
              // ── Content ──────────────────────────────────────────────────
              else ...[
                // Quick identity actions
                if (_passInfo != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.ios_share_rounded,
                          label: 'Share pass',
                          onTap: _sharePass,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.copy_rounded,
                          label: 'Copy ID',
                          onTap: _copyId,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Member pass ──────────────────────────────────────────
                Text(
                  'MEMBER PASS',
                  style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
                ),
                const SizedBox(height: 12),
                MemberPassCard(profile: profile, compact: true),
                const SizedBox(height: 28),

                // ── Find people ──────────────────────────────────────────
                Text(
                  'FIND PEOPLE',
                  style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
                ),
                const SizedBox(height: 12),
                _SearchField(
                  controller: _searchController,
                  searching: _searching,
                  onChanged: _onSearchChanged,
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final result in _results)
                    _UserRow(
                      user: result,
                      added: _isCrew(result),
                      loading: _adding.contains(result.id),
                      actionLabel: _isCrew(result) ? 'In crew' : 'Add',
                      onPressed: _isCrew(result) || _adding.contains(result.id)
                          ? null
                          : () => _addCrew(result),
                    ),
                ] else if (_searchController.text.trim().length >= 2 &&
                    !_searching) ...[
                  const SizedBox(height: 12),
                  const _EmptyNote(text: 'No matching Nuvo members found.'),
                ],
                const SizedBox(height: 28),

                // ── Your crew ────────────────────────────────────────────
                Text(
                  'YOUR CREW',
                  style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
                ),
                const SizedBox(height: 12),
                if (_crew.isEmpty)
                  const _EmptyNote(
                    text: 'Search a username or member ID to add crew.',
                  )
                else
                  for (final member in _crew)
                    _UserRow(user: member, added: true, actionLabel: 'In crew'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick action button ───────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: NuvoColors.navy, size: 16),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.labelMedium),
          ],
        ),
      ),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────

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
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
      decoration: InputDecoration(
        hintText: 'Username or member ID',
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        filled: true,
        fillColor: NuvoColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: NuvoColors.muted, size: 20),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NuvoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NuvoColors.blue, width: 1.6),
        ),
      ),
    );
  }
}

// ── User row ──────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.added = false,
    this.loading = false,
    this.actionLabel,
    this.onPressed,
  });

  final PublicUser user;
  final bool added;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.divider),
        ),
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
                style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.white),
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
                    style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              added
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        actionLabel!,
                        style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
                      ),
                    )
                  : SizedBox(
                      width: 72,
                      child: NuvoOutlineButton(
                        label: loading ? '...' : actionLabel!,
                        small: true,
                        onPressed: loading ? null : onPressed,
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}

// ── Empty note ────────────────────────────────────────────────────────────────

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}
