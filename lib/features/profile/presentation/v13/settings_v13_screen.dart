import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/legal_links.dart';
import '../../../../core/demo/presentation_demo.dart';
import '../../../../core/v13/v13.dart';
import '../../../arena/presentation/arena_controller.dart';
import '../../../auth/data/auth_api.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../notifications/data/notification_prefs.dart';
import '../../../notifications/presentation/notification_prefs_screen.dart'
    show notificationPrefsApiProvider;
import '../../../onboarding/presentation/first_use_guide.dart';
import '../../../races/data/race_models.dart';
import '../../../races/presentation/race_controller.dart';
import '../../data/profile_v13_api.dart';

/// `/settings` — the v13 settings page. Account card, notification
/// categories, privacy, app, support and account actions — every row wired
/// to a real controller or link.
class SettingsV13Screen extends ConsumerStatefulWidget {
  const SettingsV13Screen({super.key});

  @override
  ConsumerState<SettingsV13Screen> createState() => _SettingsV13ScreenState();
}

class _SettingsV13ScreenState extends ConsumerState<SettingsV13Screen> {
  /// Server prefs keyed by category; null while loading, error on failure.
  Map<String, NotificationPref>? _notifPrefs;
  Object? _notifError;

  bool? _motionConsent;
  bool _signingOut = false;
  bool _deleting = false;

  static const _demoAccountEmails = {
    'sideswifter2010@gmai.com',
    'sideswifter2010@gmail.com',
  };

  /// v13 label → server categories it groups (A17). Rows hide when none of
  /// their categories exist in the server's response.
  static const _notifGroups = <String, List<String>>{
    'Passes': ['passed_on_leaderboard'],
    'Invites': [
      'race_invite',
      'race_joined',
      'crew_request',
      'crew_request_accepted',
      'crew_connected',
    ],
    'Results': [
      'race_completed',
      'proof_accepted',
      'proof_rejected',
      'proof_disputed',
    ],
    'Cheers': ['reaction'],
    'Reminders': ['race_starting'],
  };

  static const _notifIcons = <String, IconData>{
    'Passes': Icons.swap_vert_rounded,
    'Invites': Icons.mail_outline_rounded,
    'Results': Icons.flag_outlined,
    'Cheers': Icons.favorite_outline_rounded,
    'Reminders': Icons.notifications_outlined,
  };

  static const _notifColors = <String, Color>{
    'Passes': V13.lilac,
    'Invites': V13.sky,
    'Results': V13.mint,
    'Cheers': V13.coral,
    'Reminders': V13.sun,
  };

  @override
  void initState() {
    super.initState();
    _loadNotifPrefs();
    _loadMotionConsent();
  }

  Future<void> _loadNotifPrefs() async {
    try {
      final prefs = await ref.read(notificationPrefsApiProvider).list();
      if (!mounted) return;
      setState(() {
        _notifPrefs = {for (final p in prefs) p.category: p};
        _notifError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notifError = e);
    }
  }

  Future<void> _loadMotionConsent() async {
    try {
      final consented = await ref
          .read(authControllerProvider.notifier)
          .getMotionConsent();
      if (mounted) setState(() => _motionConsent = consented);
    } catch (_) {
      // Row hides on failure — no consent read, no toggle.
    }
  }

  Future<void> _setNotifGroup(String label, List<String> cats, bool on) async {
    final prefs = _notifPrefs;
    if (prefs == null) return;
    final touched = cats.where(prefs.containsKey).toList();
    if (touched.isEmpty) return;
    // Optimistic flip; rollback on any failure.
    final previous = {for (final c in touched) c: prefs[c]!.push};
    setState(() {
      for (final c in touched) {
        final p = prefs[c]!;
        prefs[c] = NotificationPref(
          category: p.category,
          inApp: p.inApp,
          push: on,
        );
      }
    });
    try {
      for (final c in touched) {
        await ref.read(notificationPrefsApiProvider).update(c, push: on);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final c in touched) {
          final p = prefs[c]!;
          prefs[c] = NotificationPref(
            category: p.category,
            inApp: p.inApp,
            push: previous[c] ?? true,
          );
        }
      });
      showV13Toast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final c in touched) {
          final p = prefs[c]!;
          prefs[c] = NotificationPref(
            category: p.category,
            inApp: p.inApp,
            push: previous[c] ?? true,
          );
        }
      });
      showV13Toast(context, "Couldn't save that. Try again.");
    }
  }

  Future<void> _setActivityMapShared(bool on) async {
    final current = ref.read(profilePrefsProvider).valueOrNull;
    if (current == null) return;
    try {
      await ref.read(profileV13ApiProvider).updatePrefs(activityMapShared: on);
      ref.invalidate(profilePrefsProvider);
    } on ApiException catch (e) {
      if (mounted) showV13Toast(context, e.message);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't save that. Try again.");
      }
    }
  }

  Future<void> _pickRaceInvites(NuvoProfilePrefs prefs) async {
    final choice = await showV13ActionSheet<String>(
      context,
      title: 'Who can race me',
      actions: const [
        V13SheetAction(label: 'Everyone', value: 'everyone'),
        V13SheetAction(label: 'Friends only', value: 'friends'),
      ],
    );
    if (choice == null || !mounted) return;
    try {
      await ref
          .read(profileV13ApiProvider)
          .updatePrefs(raceInvitesFrom: choice);
      ref.invalidate(profilePrefsProvider);
    } on ApiException catch (e) {
      if (mounted) showV13Toast(context, e.message);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't save that. Try again.");
      }
    }
  }

  Future<void> _setMotionConsent(bool on) async {
    final previous = _motionConsent;
    setState(() => _motionConsent = on);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setMotionConsent(consented: on);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _motionConsent = previous);
      if (e.statusCode == 403 && on) {
        // Consent needs a 13+ attestation first — same flow as before.
        final yes = await showV13ConfirmSheet(
          context,
          title: 'Help improve AI Motion?',
          body:
              'Confirm you are 13 or older to send anonymized motion '
              'frames that improve Nuvo\'s verifier.',
          confirmLabel: 'I\'m 13 or older',
        );
        if (yes == true && mounted) {
          try {
            await ref.read(authControllerProvider.notifier).attestAge();
            await ref
                .read(authControllerProvider.notifier)
                .setMotionConsent(consented: true);
            if (mounted) setState(() => _motionConsent = true);
          } catch (_) {
            if (mounted) {
              showV13Toast(context, "Couldn't save that. Try again.");
            }
          }
        }
      } else {
        showV13Toast(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _motionConsent = previous);
        showV13Toast(context, "Couldn't save that. Try again.");
      }
    }
  }

  Future<void> _setPresentationMode(bool enabled) async {
    if (!canTogglePresentationMode(ref.read(authControllerProvider).user)) {
      return;
    }
    try {
      final persistence = setPresentationModeEnabled(enabled);
      final races = ref.read(raceControllerProvider.notifier)..clearRaces();
      final arena = ref.read(arenaControllerProvider.notifier)..clearSnapshot();
      await Future.wait([
        persistence,
        races.loadRaces(force: true),
        arena.loadSnapshot(force: true),
      ]);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, 'Something went wrong. Try again.');
      }
    }
  }

  Future<void> _contactSupport() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('mailto:support@getnuvo.net'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showV13Toast(context, "Couldn't open the mail app. Try again.");
    }
  }

  Future<void> _replayDemo() async {
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    ref.read(demoReplayProvider.notifier).state = true;
    if (mounted) context.go('/splash');
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {
      if (mounted) {
        setState(() => _signingOut = false);
        showV13Toast(context, "Couldn't sign out. Try again.");
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showV13ConfirmSheet(
      context,
      title: 'Delete account?',
      body:
          'This permanently deletes your Nuvo account and signs you out '
          'on all devices. You can\'t undo it from the app.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) context.go('/welcome');
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        showV13Toast(context, 'Could not delete account. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(presentationModeEnabledProvider);
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final prefs = ref.watch(profilePrefsProvider).valueOrNull;
    final haptics = ref.watch(v13HapticsEnabledProvider);
    final presentationOn = presentationModeToggleEnabled;
    final canReplayDemo =
        user != null &&
        _demoAccountEmails.contains(user.email.trim().toLowerCase());
    final canTogglePresentation =
        user != null && canTogglePresentationMode(user);

    return Scaffold(
      backgroundColor: V13.bg,
      // bottom: false — the list scrolls to the screen edge (behind the home
      // indicator) instead of stopping at the safe inset with a blank strip.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const V13BackBar(title: 'Settings'),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  V13.pagePad,
                  V13.gapMd,
                  V13.pagePad,
                  MediaQuery.paddingOf(context).bottom + V13.gapXxl * 2,
                ),
                children: [
                  _accountCard(
                    user?.fullName ?? 'Nuvo member',
                    user?.username,
                    user?.profilePhotoUrl,
                  ),
                  const SizedBox(height: V13.gapSection),
                  _notificationsSection(),
                  const SizedBox(height: V13.gapSection),
                  _privacySection(prefs),
                  const SizedBox(height: V13.gapSection),
                  _appSection(
                    haptics: haptics,
                    presentationOn: presentationOn,
                    canTogglePresentation: canTogglePresentation,
                    canReplayDemo: canReplayDemo,
                  ),
                  const SizedBox(height: V13.gapSection),
                  _supportSection(),
                  const SizedBox(height: V13.gapSection),
                  _accountSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(String name, String? username, String? photoUrl) {
    return V13Card(
      onTap: () => context.push('/profile/edit'),
      padding: const EdgeInsets.all(V13.gapLg),
      child: Row(
        children: [
          V13Face(photoUrl: photoUrl, size: 56, isMe: true, name: name),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: V13.bodyStrong),
                if (username != null && username.isNotEmpty)
                  Text('@$username', style: V13.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: V13.muted),
        ],
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return V13Card(
      padding: const EdgeInsets.symmetric(horizontal: V13.gapLg),
      child: Column(children: children),
    );
  }

  Widget _notificationsSection() {
    final prefs = _notifPrefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'NOTIFICATIONS'),
        const SizedBox(height: V13.gapMd),
        if (prefs == null && _notifError == null)
          _sectionCard(const [
            Padding(
              padding: EdgeInsets.all(V13.gapLg),
              child: V13Skeleton(height: 44, radius: V13.radiusTile),
            ),
          ])
        else if (prefs == null)
          _sectionCard([
            V13ListRow(
              title: 'Couldn\'t load notifications',
              subtitle: 'Try again',
              leading: const V13IconTile(icon: Icons.refresh_rounded),
              showDivider: false,
              onTap: _loadNotifPrefs,
            ),
          ])
        else
          _sectionCard([
            for (final (i, entry) in _notifGroups.entries.indexed) ...[
              if (entry.value.any(prefs.containsKey))
                V13ListRow(
                  title: entry.key,
                  leading: V13IconTile(
                    icon: _notifIcons[entry.key]!,
                    color: _notifColors[entry.key]!,
                  ),
                  showDivider: i < _notifGroups.length - 1,
                  trailing: V13Toggle(
                    value: entry.value
                        .where(prefs.containsKey)
                        .every((c) => prefs[c]!.push),
                    onChanged: (on) =>
                        _setNotifGroup(entry.key, entry.value, on),
                  ),
                ),
            ],
          ]),
      ],
    );
  }

  Widget _privacySection(NuvoProfilePrefs? prefs) {
    final showActivity = prefs?.hasActivityMapShared == true;
    final showRaceScope = prefs?.hasRaceInvitesFrom == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'PRIVACY'),
        const SizedBox(height: V13.gapMd),
        _sectionCard([
          if (showActivity)
            V13ListRow(
              title: 'Show my activity map',
              leading: const V13IconTile(
                icon: Icons.grid_on_rounded,
                color: V13.mint,
              ),
              trailing: V13Toggle(
                value: prefs!.activityMapShared ?? true,
                onChanged: _setActivityMapShared,
              ),
            ),
          if (showRaceScope)
            V13ListRow(
              title: 'Who can race me',
              subtitle: (prefs!.raceInvitesFrom ?? 'everyone') == 'friends'
                  ? 'Friends only'
                  : 'Everyone',
              leading: const V13IconTile(
                icon: Icons.group_outlined,
                color: V13.sky,
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: V13.muted,
              ),
              onTap: () => _pickRaceInvites(prefs),
            ),
          V13ListRow(
            title: 'Blocked accounts',
            leading: const V13IconTile(
              icon: Icons.block_rounded,
              color: V13.coral,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            showDivider: false,
            onTap: _blockedSheet,
          ),
        ]),
      ],
    );
  }

  Future<void> _blockedSheet() async {
    List<PublicUser> blocked;
    try {
      blocked = await ref.read(crewRepositoryProvider).getBlocked();
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't load blocked accounts. Try again.");
      }
      return;
    }
    if (!mounted) return;
    await showV13Sheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            V13.pagePad,
            0,
            V13.pagePad,
            V13.pagePad,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Blocked accounts', style: V13.sectionHead),
              const SizedBox(height: V13.gapMd),
              if (blocked.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(V13.gapLg),
                  child: Text(
                    'Nobody blocked. People you block disappear from your '
                    'friends, races and feed.',
                    style: V13.body,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final user in blocked)
                        V13ListRow(
                          title: user.displayName,
                          subtitle: user.username != null
                              ? '@${user.username}'
                              : null,
                          leading: V13Face(
                            photoUrl: user.profilePhotoUrl,
                            size: 40,
                            name: user.displayName,
                          ),
                          trailing: V13Button.secondary(
                            label: 'Unblock',
                            size: V13ButtonSize.small,
                            onPressed: () async {
                              try {
                                await ref
                                    .read(crewRepositoryProvider)
                                    .unblockUser(user.id);
                                setSheetState(
                                  () => blocked = [
                                    for (final u in blocked)
                                      if (u.id != user.id) u,
                                  ],
                                );
                                ref
                                    .read(crewControllerProvider.notifier)
                                    .load();
                                if (context.mounted) {
                                  showV13Toast(
                                    context,
                                    'Unblocked ${user.displayName}.',
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  showV13Toast(
                                    context,
                                    "Couldn't unblock them. Try again.",
                                  );
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appSection({
    required bool haptics,
    required bool presentationOn,
    required bool canTogglePresentation,
    required bool canReplayDemo,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'APP'),
        const SizedBox(height: V13.gapMd),
        _sectionCard([
          V13ListRow(
            title: 'Haptics',
            leading: const V13IconTile(
              icon: Icons.vibration_rounded,
              color: V13.lilac,
            ),
            trailing: V13Toggle(
              value: haptics,
              onChanged: (on) => setV13HapticsEnabled(on),
            ),
          ),
          if (_motionConsent != null)
            V13ListRow(
              title: 'Help improve AI Motion',
              subtitle: 'Share anonymized motion frames',
              leading: const V13IconTile(
                icon: Icons.sports_gymnastics_rounded,
                color: V13.mint,
              ),
              trailing: V13Toggle(
                value: _motionConsent!,
                onChanged: _setMotionConsent,
              ),
            ),
          if (canTogglePresentation)
            V13ListRow(
              title: 'Presentation mode',
              leading: const V13IconTile(
                icon: Icons.slideshow_rounded,
                color: V13.sky,
              ),
              trailing: V13Toggle(
                value: presentationOn,
                onChanged: _setPresentationMode,
              ),
            ),
          if (canReplayDemo || kDebugMode)
            V13ListRow(
              title: 'Replay the intro',
              leading: const V13IconTile(
                icon: Icons.replay_rounded,
                color: V13.sun,
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: V13.muted,
              ),
              showDivider: false,
              onTap: _replayDemo,
            ),
        ]),
      ],
    );
  }

  Widget _supportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'SUPPORT'),
        const SizedBox(height: V13.gapMd),
        _sectionCard([
          V13ListRow(
            title: 'Help & contact',
            leading: const V13IconTile(
              icon: Icons.mail_outline_rounded,
              color: V13.sky,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: _contactSupport,
          ),
          V13ListRow(
            title: 'Community Guidelines',
            leading: const V13IconTile(
              icon: Icons.handshake_outlined,
              color: V13.mint,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: () =>
                openLegalLink(context, LegalLinks.communityGuidelinesUri),
          ),
          V13ListRow(
            title: 'Privacy Policy',
            leading: const V13IconTile(
              icon: Icons.shield_outlined,
              color: V13.lilac,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: () => openLegalLink(context, LegalLinks.privacyUri),
          ),
          V13ListRow(
            title: 'Terms of Service',
            leading: const V13IconTile(
              icon: Icons.description_outlined,
              color: V13.sun,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: V13.muted),
            showDivider: false,
            onTap: () => openLegalLink(context, LegalLinks.termsUri),
          ),
        ]),
      ],
    );
  }

  Widget _accountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const V13SectionHeader(title: 'ACCOUNT'),
        const SizedBox(height: V13.gapMd),
        _sectionCard([
          V13ListRow(
            title: 'Sign out',
            leading: const V13IconTile(
              icon: Icons.logout_rounded,
              color: V13.sky,
            ),
            trailing: _signingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: V13.navy,
                    ),
                  )
                : const Icon(Icons.chevron_right_rounded, color: V13.muted),
            onTap: _signingOut ? null : _signOut,
          ),
          V13ListRow(
            title: 'Delete account',
            leading: const V13IconTile(
              icon: Icons.delete_outline_rounded,
              color: V13.coral,
            ),
            trailing: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: V13.navy,
                    ),
                  )
                : const Icon(Icons.chevron_right_rounded, color: V13.muted),
            showDivider: false,
            onTap: _deleting ? null : _deleteAccount,
          ),
        ]),
      ],
    );
  }
}
