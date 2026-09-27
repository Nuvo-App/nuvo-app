import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../crew/application/crew_controller.dart';
import '../../crew/data/crew_api.dart';
import '../../races/data/race_models.dart' show PublicUser;

/// `/crew/add` — the dedicated Add to Crew hub. One surface for every way to
/// connect: search, scan, share your code, and the requests queue. Reuses
/// `/users/search` (name, @username, member code), the crew lifecycle, and
/// the QR/deep-link stack — nothing is duplicated server-side.
class AddCrewScreen extends ConsumerStatefulWidget {
  const AddCrewScreen({super.key});

  @override
  ConsumerState<AddCrewScreen> createState() => _AddCrewScreenState();
}

class _AddCrewScreenState extends ConsumerState<AddCrewScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<CrewSearchResult> _results = const [];
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results =
            await ref.read(crewControllerProvider.notifier).search(query);
        if (mounted) {
          setState(() {
            _results = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _searching = false;
            _searchError = 'Search failed. Try again.';
          });
        }
      }
    });
  }

  Future<void> _add(PublicUser user) async {
    try {
      final outcome =
          await ref.read(crewControllerProvider.notifier).add(user);
      if (mounted && outcome == ConnectOutcome.pending) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request sent.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add this crew member.')),
        );
      }
    }
  }

  Future<void> _accept(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(user);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't accept the request.")),
        );
      }
    }
  }

  Future<void> _decline(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).declineRequest(user);
    } catch (_) {
      /* best-effort */
    }
  }

  @override
  Widget build(BuildContext context) {
    final crewState = ref.watch(crewControllerProvider);
    final pending = crewState.pendingUserIds;
    final searching = _searchController.text.trim().length >= 2;
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            NuvoBackButton(onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/pass');
              }
            }),
          ]),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text('Add to crew', style: AppTextStyles.displaySmall),
            const SizedBox(height: 4),
            Text(
              'Name, @username or member code.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: NuvoColors.textMuted),
            ),
            const SizedBox(height: 16),
            NuvoSearchField(
              controller: _searchController,
              hint: 'Search Nuvo members',
              searching: _searching,
              autofocus: true,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            // The other three ways in — scan theirs, show yours, share a link.
            Row(
              children: [
                Expanded(
                  child: _WayIn(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan',
                    onTap: () => context.push('/scan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WayIn(
                    icon: Icons.qr_code_rounded,
                    label: 'My Nuvo',
                    onTap: () => context.push('/my-nuvo'),
                  ),
                ),
              ],
            ),

            // ── Search results ─────────────────────────────────────────
            if (searching) ...[
              const SizedBox(height: 16),
              if (_searchError != null && !_searching)
                NuvoPressable(
                  onTap: () => _onSearchChanged(_searchController.text),
                  haptic: false,
                  child: _HubNote(text: _searchError!),
                )
              else if (_results.isEmpty && !_searching)
                const _HubNote(text: 'No matching Nuvo members found.')
              else
                _HubSurface(
                  children: [
                    for (var i = 0; i < _results.length; i++)
                      _PersonRow(
                        result: _results[i],
                        busy: pending.contains(_results[i].user.id),
                        isLast: i == _results.length - 1,
                        onOpen: () =>
                            context.push('/u/${_results[i].user.id}'),
                        onAdd: () => _add(_results[i].user),
                        onAccept: () => _accept(_results[i].user),
                      ),
                  ],
                ),
            ] else ...[
              // ── Requests — people already knocking ────────────────────
              if (crewState.requests.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _HubLabel(label: 'Wants in your crew'),
                const SizedBox(height: 10),
                _HubSurface(
                  children: [
                    for (var i = 0; i < crewState.requests.length; i++)
                      _RequestRow(
                        user: crewState.requests[i],
                        busy: pending.contains(crewState.requests[i].id),
                        isLast: i == crewState.requests.length - 1,
                        onAccept: () => _accept(crewState.requests[i]),
                        onDecline: () => _decline(crewState.requests[i]),
                      ),
                  ],
                ),
              ],
              if (crewState.outgoing.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _HubLabel(label: 'Requests sent'),
                const SizedBox(height: 10),
                _HubSurface(
                  children: [
                    for (var i = 0; i < crewState.outgoing.length; i++)
                      _SentRow(
                        user: crewState.outgoing[i],
                        isLast: i == crewState.outgoing.length - 1,
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WayIn extends StatelessWidget {
  const _WayIn({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NuvoColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: NuvoPressable(
        onTap: onTap,
        haptic: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NuvoColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: NuvoColors.navy),
              const SizedBox(width: 8),
              Text(label,
                  style: AppTextStyles.labelLarge
                      .copyWith(color: NuvoColors.navy)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubSurface extends StatelessWidget {
  const _HubSurface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _HubLabel extends StatelessWidget {
  const _HubLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppTextStyles.sectionTitle);
}

class _HubNote extends StatelessWidget {
  const _HubNote({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style:
              AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
        ),
      );
}

String _handleLine(PublicUser user) {
  final parts = <String>[];
  if (user.username != null && user.username!.isNotEmpty) {
    parts.add('@${user.username}');
  }
  if (user.memberId != null && user.memberId!.isNotEmpty) {
    parts.add(user.memberId!);
  }
  return parts.join(' / ');
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.result,
    required this.busy,
    required this.isLast,
    required this.onOpen,
    required this.onAdd,
    required this.onAccept,
  });

  final CrewSearchResult result;
  final bool busy;
  final bool isLast;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final user = result.user;
    final mutual = result.mutualCount;
    final subtitle = [
      if (_handleLine(user).isNotEmpty) _handleLine(user),
      if (mutual > 0)
        '$mutual mutual ${mutual == 1 ? 'crew' : 'crew'}',
    ].join(' · ');
    return Column(
      children: [
        NuvoPressable(
          onTap: onOpen,
          haptic: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                NuvoAvatar(
                  initials: user.initials,
                  photoUrl: user.profilePhotoUrl,
                  size: NuvoAvatarSizes.md,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: NuvoColors.textMuted),
                        ),
                    ],
                  ),
                ),
                _cta(),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: NuvoColors.border, indent: 60),
      ],
    );
  }

  Widget _cta() {
    return NuvoStateMorph(
      stateKey: result.connectionStatus,
      child: switch (result.connectionStatus) {
        CrewConnectionStatus.connected =>
          const _StatusChip(label: 'In crew', color: NuvoColors.success),
        CrewConnectionStatus.pendingOutgoing =>
          const _StatusChip(label: 'Sent', color: NuvoColors.warning),
        CrewConnectionStatus.pendingIncoming => NuvoPrimaryButton(
            label: 'Accept',
            loading: busy,
            onPressed: busy ? null : onAccept,
          ),
        CrewConnectionStatus.none => NuvoPrimaryButton(
            label: 'Add',
            loading: busy,
            onPressed: busy ? null : onAdd,
          ),
      },
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.user,
    required this.busy,
    required this.isLast,
    required this.onAccept,
    required this.onDecline,
  });

  final PublicUser user;
  final bool busy;
  final bool isLast;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              NuvoAvatar(
                initials: user.initials,
                photoUrl: user.profilePhotoUrl,
                size: NuvoAvatarSizes.md,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_handleLine(user).isNotEmpty)
                      Text(
                        _handleLine(user),
                        style: AppTextStyles.bodySmall
                            .copyWith(color: NuvoColors.textMuted),
                      ),
                  ],
                ),
              ),
              NuvoPrimaryButton(
                label: 'Accept',
                loading: busy,
                onPressed: busy ? null : onAccept,
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: busy ? null : onDecline,
                icon: const Icon(Icons.close_rounded,
                    color: NuvoColors.muted, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: NuvoColors.border, indent: 60),
      ],
    );
  }
}

class _SentRow extends StatelessWidget {
  const _SentRow({required this.user, required this.isLast});
  final PublicUser user;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              NuvoAvatar(
                initials: user.initials,
                photoUrl: user.profilePhotoUrl,
                size: NuvoAvatarSizes.md,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const _StatusChip(label: 'Sent', color: NuvoColors.warning),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: NuvoColors.border, indent: 60),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}
