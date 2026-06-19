import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
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
      final passFuture = ref
          .read(authControllerProvider.notifier)
          .getMemberPass();
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

  bool _isCrew(PublicUser user) => _crew.any((member) => member.id == user.id);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = _buildProfile(user);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('Crew', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 6),
            Text(
              'Find people by username or member ID.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              NuvoErrorState(message: _error!, onRetry: _fetch)
            else ...[
              const NuvoSectionHeader(title: 'Your member pass'),
              MemberPassCard(profile: profile, compact: true),
              const SizedBox(height: 20),
              const NuvoSectionHeader(title: 'Find people'),
              _SearchField(
                controller: _searchController,
                searching: _searching,
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 12),
              if (_results.isNotEmpty)
                for (final result in _results)
                  _UserRow(
                    user: result,
                    added: _isCrew(result),
                    loading: _adding.contains(result.id),
                    actionLabel: _isCrew(result) ? 'Added' : 'Add',
                    onPressed: _isCrew(result) || _adding.contains(result.id)
                        ? null
                        : () => _addCrew(result),
                  )
              else if (_searchController.text.trim().length >= 2 && !_searching)
                const _SmallEmpty(text: 'No matching Nuvo members found.'),
              const SizedBox(height: 20),
              const NuvoSectionHeader(title: 'Your crew'),
              if (_crew.isEmpty)
                const _SmallEmpty(
                  text:
                      'Search a username or member ID to add your first crew member.',
                )
              else
                for (final member in _crew)
                  _UserRow(user: member, added: true, actionLabel: 'Added'),
            ],
          ],
        ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: NuvoCompactCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            if (actionLabel != null)
              SizedBox(
                width: 84,
                child: NuvoOutlineButton(
                  label: loading ? '...' : actionLabel!,
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

class _SmallEmpty extends StatelessWidget {
  const _SmallEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return NuvoCompactCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}
