import '../../../core/offline/online_gate.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/races/data/race_models.dart' show PublicUser;

import 'v13/crew_tab_v13_widgets.dart';

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
  void initState() {
    super.initState();
    // Same self-kick the shell gives the Crew tab — the queue is fresh even
    // when this screen is the first social surface opened.
    Future(() {
      if (!mounted) return;
      ref.read(crewControllerProvider.notifier).revalidate();
    });
  }

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
        final results = await ref
            .read(crewControllerProvider.notifier)
            .search(query);
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
      final outcome = await ref.read(crewControllerProvider.notifier).add(user);
      if (mounted && outcome == ConnectOutcome.pending) {
        showV13Toast(context, 'Request sent.');
      }
    } catch (_) {
      if (mounted) showV13Toast(context, 'Could not add this friend.');
    }
  }

  Future<void> _accept(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).acceptRequest(user);
      if (!mounted) return;
      V13Haptics.confirm();
      showV13Confetti(context);
      showV13Toast(
        context,
        "You're friends with ${user.displayName.split(' ').first}.",
      );
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't accept the request.");
    }
  }

  Future<void> _decline(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).declineRequest(user);
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't decline. Try again.");
    }
  }

  Future<void> _cancelOutgoing(PublicUser user) async {
    try {
      await ref.read(crewControllerProvider.notifier).remove(user.id);
      if (mounted) showV13Toast(context, 'Request cancelled.');
    } catch (_) {
      if (mounted) showV13Toast(context, "Couldn't cancel. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final crewState = ref.watch(crewControllerProvider);
    final pending = crewState.pendingUserIds;
    final searching = _searchController.text.trim().length >= 2;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'Add friend', fallback: '/pass'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  V13.pagePad,
                  0,
                  V13.pagePad,
                  V13.gapXxl,
                ),
                children: [
                  Text('Name, @username or member code.', style: V13.caption),
                  const SizedBox(height: V13.gapMd),
                  V13TextInput(
                    controller: _searchController,
                    enabled: appOnline(ref),
                    hint: appOnline(ref)
                        ? 'Search Nuvo members'
                        : 'Search needs internet',
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: V13.muted,
                    ),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(
                              dimension: 16,
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
                  // The other two ways in — scan theirs, show yours.
                  Row(
                    children: [
                      Expanded(
                        child: V13Button.secondary(
                          label: 'Scan',
                          icon: Icons.qr_code_scanner_rounded,
                          fullWidth: true,
                          onPressed: () => openScan(context),
                        ),
                      ),
                      const SizedBox(width: V13.gapMd),
                      Expanded(
                        child: V13Button.secondary(
                          label: 'My Nuvo',
                          icon: Icons.qr_code_rounded,
                          fullWidth: true,
                          onPressed: () => context.push('/my-nuvo'),
                        ),
                      ),
                    ],
                  ),

                  // ── Search results ───────────────────────────────────────
                  if (searching)
                    _searchResults(pending)
                  else
                    _requests(crewState, pending),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchResults(Set<String> pending) {
    if (_searchError != null && !_searching) {
      return CrewSectionError(
        message: _searchError!,
        onRetry: () => _onSearchChanged(_searchController.text),
      );
    }
    if (_results.isEmpty) {
      if (_searching) {
        return const Column(
          children: [
            SizedBox(height: V13.gapMd),
            V13Skeleton.box(width: double.infinity, height: 56),
            SizedBox(height: V13.gapMd),
            V13Skeleton.box(width: double.infinity, height: 56),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapLg),
        child: Center(
          child: Text('No matching Nuvo members found.', style: V13.caption),
        ),
      );
    }
    return Column(
      children: [
        const SizedBox(height: V13.gapMd),
        for (var i = 0; i < _results.length; i++)
          _personRow(_results[i], pending, i == _results.length - 1),
      ],
    );
  }

  Widget _personRow(CrewSearchResult result, Set<String> pending, bool isLast) {
    final user = result.user;
    final mutual = result.mutualCount;
    final subtitle = [
      user.handleLine,
      if (mutual > 0) '$mutual mutual ${mutual == 1 ? 'friend' : 'friends'}',
    ].join(' · ');
    return V13ListRow(
      leading: V13Face(photoUrl: user.profilePhotoUrl, name: user.displayName),
      title: user.displayName,
      subtitle: subtitle,
      trailing: _cta(result, pending.contains(user.id)),
      onTap: () => openPerson(context, ref, user.id),
      showDivider: !isLast,
    );
  }

  Widget _cta(CrewSearchResult result, bool busy) {
    return switch (result.connectionStatus) {
      CrewConnectionStatus.connected => const V13Pill(
        label: 'Friends',
        color: V13.mint,
      ),
      CrewConnectionStatus.pendingOutgoing => const V13Pill(
        label: 'Requested',
        color: V13.lilac,
      ),
      CrewConnectionStatus.pendingIncoming => V13Button.primary(
        label: 'Accept',
        size: V13ButtonSize.small,
        loading: busy,
        onPressed: busy ? null : () => _accept(result.user),
      ),
      CrewConnectionStatus.none => V13Button.secondary(
        label: 'Add',
        size: V13ButtonSize.small,
        loading: busy,
        onPressed: busy ? null : () => _add(result.user),
      ),
    };
  }

  Widget _requests(CrewState crewState, Set<String> pending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Requests — people already knocking ──────────────────────────
        if (crewState.requests.isNotEmpty) ...[
          const SizedBox(height: V13.gapSection),
          const V13SectionHeader(title: 'Wants to be friends'),
          const SizedBox(height: V13.gapMd),
          for (final user in crewState.requests) ...[
            FriendRequestCard(
              user: user,
              mutuals: crewState.mutuals[user.id],
              busy: pending.contains(user.id),
              onAccept: () => _accept(user),
              onDecline: () => _decline(user),
            ),
            const SizedBox(height: V13.gapMd),
          ],
        ],
        if (crewState.outgoing.isNotEmpty) ...[
          const SizedBox(height: V13.gapSection),
          const V13SectionHeader(title: 'Requests sent'),
          const SizedBox(height: V13.gapSm),
          for (final user in crewState.outgoing)
            OutgoingRequestRow(
              user: user,
              busy: pending.contains(user.id),
              onCancel: () => _cancelOutgoing(user),
            ),
        ],
      ],
    );
  }
}
