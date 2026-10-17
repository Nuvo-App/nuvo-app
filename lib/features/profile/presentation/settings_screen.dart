part of 'profile_screen.dart';

/// `/settings` — the administrative side of Profile: account, privacy and
/// legal. Profile itself stays about who I am and what I've done; everything
/// that configures the account lives here, one tap away.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _demoAccountEmails = {
    'sideswifter2010@gmai.com',
    'sideswifter2010@gmail.com',
  };

  Future<void> _replayDemo() async {
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    ref.read(demoReplayProvider.notifier).state = true;
    if (mounted) context.go('/splash');
  }

  Future<void> _setPresentationMode(bool enabled) async {
    if (!canTogglePresentationMode(ref.read(authControllerProvider).user)) {
      return;
    }
    final persistence = setPresentationModeEnabled(enabled);
    // Clear generations before loading so an older request cannot restore the
    // previous mode. Crew and notifications observe the preference directly.
    final races = ref.read(raceControllerProvider.notifier)..clearRaces();
    final arena = ref.read(arenaControllerProvider.notifier)..clearSnapshot();
    await Future.wait([
      persistence,
      races.loadRaces(force: true),
      arena.loadSnapshot(force: true),
    ]);
  }

  /// Opens a legal page in the in-app browser, falling back to the system
  /// browser, and says so out loud if neither works.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    var opened = false;
    for (final mode in const [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]) {
      try {
        opened = await launchUrl(uri, mode: mode);
      } catch (_) {
        opened = false;
      }
      if (opened) break;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that page. Try again.")),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: 'Delete account?',
      message:
          'This will permanently delete your Nuvo account and log you out on all devices. '
          'This action cannot be undone from the app.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) context.go('/welcome');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete account. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    ref.watch(presentationModeEnabledProvider);
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final canReplayDemo =
        user != null &&
        _demoAccountEmails.contains(user.email.trim().toLowerCase());
    final canTogglePresentation =
        user != null && canTogglePresentationMode(user);

    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: ListView(
          // Pushed pages reserve real breathing room below the last row.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
          children: [
            NuvoBackHeader(
              title: 'Settings',
              onBack: () => safePopOrGo(context, '/profile'),
            ),
            const SizedBox(height: NuvoSpacing.lg),

            // Gated tools only — this group doesn't exist for normal
            // accounts. Presentation/demo controls stay behind the existing
            // account gates.
            if (canReplayDemo || canTogglePresentation || kDebugMode) ...[
              const _SectionLabel(label: 'App'),
              const SizedBox(height: NuvoSpacing.md),
              _ProfileActionGroup(
                children: [
                  if (canReplayDemo)
                    _AccountRow(
                      icon: Icons.replay_rounded,
                      label: 'Replay the guide',
                      onTap: _replayDemo,
                    ),
                  if (canTogglePresentation)
                    _PresentationModeRow(
                      enabled: presentationModeToggleEnabled,
                      onChanged: _setPresentationMode,
                    ),
                  if (kDebugMode)
                    _AccountRow(
                      icon: Icons.tune_rounded,
                      label: 'Rive Calibration',
                      onTap: () => context.push('/dev/rive-calibration'),
                    ),
                ],
              ),
              const SizedBox(height: NuvoSpacing.xl),
            ],

            // Privacy & Data — the server-backed training-consent control.
            // Same choice as onboarding; toggling writes through to the
            // account.
            const _SectionLabel(label: 'Privacy & Data'),
            const SizedBox(height: NuvoSpacing.md),
            const _ProfileActionGroup(children: [_MotionConsentRow()]),
            const SizedBox(height: NuvoSpacing.xl),

            // Account — session actions. Destructive red belongs to Delete
            // alone; Sign out is a normal action, not a danger.
            const _SectionLabel(label: 'Account'),
            const SizedBox(height: NuvoSpacing.md),
            _ProfileActionGroup(
              children: [
                _AccountRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Edit profile',
                  subtitle: 'Photo, name, username',
                  onTap: () => context.push('/profile/edit'),
                ),
                _AccountRow(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  isAction: true,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
                _AccountRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete account',
                  isDanger: true,
                  onTap: _confirmDeleteAccount,
                ),
              ],
            ),
            const SizedBox(height: NuvoSpacing.xl),

            // Legal
            const _SectionLabel(label: 'Legal'),
            const SizedBox(height: NuvoSpacing.md),
            _ProfileActionGroup(
              children: [
                _AccountRow(
                  icon: Icons.policy_rounded,
                  label: 'Privacy Policy',
                  onTap: () => _openUrl(_kPrivacyUrl),
                ),
                _AccountRow(
                  icon: Icons.description_rounded,
                  label: 'Terms of Service',
                  onTap: () => _openUrl(_kTermsUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
