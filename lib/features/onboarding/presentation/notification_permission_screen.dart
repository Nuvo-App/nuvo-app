import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../notifications/application/push_service.dart';
import '../data/first_use_store.dart';

/// First-run notification education — the single permission moment between
/// the Nuvo story and the first-race guide.
///
/// Ordering contract: the screen only renders when the OS authorization is
/// genuinely undecided (checked async on mount; authorized / provisional /
/// denied / unavailable all resolve silently — a denied OS state can't
/// re-prompt anyway, and Settings owns the way back). The system dialog
/// fires ONLY from the "Turn on notifications" tap — never on load.
///
/// Resolving (any path) clears the first-use owed flag and hands the user
/// to /arena, where the existing guide-arm logic takes over.
class NotificationPermissionScreen extends ConsumerStatefulWidget {
  const NotificationPermissionScreen({super.key});

  @override
  ConsumerState<NotificationPermissionScreen> createState() =>
      _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState
    extends ConsumerState<NotificationPermissionScreen> {
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthorization());
  }

  Future<void> _checkAuthorization() async {
    final status =
        await ref.read(pushServiceProvider).notificationAuthorizationStatus();
    if (!mounted) return;
    if (status != AuthorizationStatus.notDetermined) {
      await _resolve();
      return;
    }
    setState(() => _ready = true);
  }

  /// Every exit lands here: the step counts as resolved once shown, so it
  /// never replays on later launches — and the owed flag is what the route
  /// guard resumes from.
  Future<void> _resolve() async {
    await ref.read(firstUseStoreProvider).clearNotificationPromptOwed();
    if (mounted) context.go('/arena');
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // The OS dialog itself lives behind this tap — grant, deny, or an
      // unavailable transport all continue first-run identically.
      await ref.read(pushServiceProvider).requestPermissionInContext();
    } catch (_) {
      // Permission transport hiccups must not trap onboarding.
    }
    await _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Scaffold(
      backgroundColor: c.page,
      body: SafeArea(
        child: !_ready
            ? const Center(child: NuvoLoadingIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Bell mark — same circle-token language
                                    // as the consent facts above it.
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c.panel,
                                        border: Border.all(
                                          color: c.ink,
                                          width: 1.6,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.notifications_active_rounded,
                                        color: NuvoColors.blue,
                                        size: 26,
                                      ),
                                    ).animate().fadeIn(duration: 280.ms).scale(
                                          begin: const Offset(.85, .85),
                                          duration: 280.ms,
                                          curve: Curves.easeOutBack,
                                        ),
                                    const SizedBox(height: 22),
                                    Text(
                                      'Don’t miss the move.',
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.headlineLarge
                                          .copyWith(
                                            fontSize: 32,
                                            letterSpacing: -0.9,
                                            color: c.ink,
                                          ),
                                    ).animate(delay: 120.ms).fadeIn(
                                          duration: 280.ms,
                                        ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Know when someone passes you, '
                                      'submits proof, or pulls you '
                                      'into a race.',
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: c.inkMuted,
                                        height: 1.45,
                                      ),
                                    ).animate(delay: 240.ms).fadeIn(
                                          duration: 280.ms,
                                        ),
                                    const SizedBox(height: 28),
                                    // The examples ARE the argument — two
                                    // real notification shapes, layered.
                                    const _SampleNoticeStack()
                                        .animate(delay: 340.ms)
                                        .fadeIn(duration: 300.ms)
                                        .slideY(begin: .12, duration: 300.ms),
                                  ],
                                ),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    NuvoPrimaryButton(
                      label: 'Turn on notifications',
                      icon: Icons.notifications_rounded,
                      expand: true,
                      loading: _busy,
                      onPressed: _enable,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _busy ? null : _resolve,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: c.ink,
                        ),
                        child: Text(
                          'Maybe later',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Two stacked sample notifications — an overtake and an accepted proof —
/// offset like cards about to be dealt. They explain why notifications
/// matter without a paragraph of copy.
class _SampleNoticeStack extends StatelessWidget {
  const _SampleNoticeStack();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(-8, 34),
            child: Transform.rotate(
              angle: -0.03,
              child: const _SampleNotice(
                icon: Icons.north_east_rounded,
                iconColor: NuvoColors.blue,
                title: 'Noah passed you',
                subtitle: 'Pushup Battle · you’re 2nd now',
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(8, -30),
            child: Transform.rotate(
              angle: 0.025,
              child: const _SampleNotice(
                icon: Icons.check_circle_rounded,
                iconColor: NuvoColors.success,
                title: 'Maya’s proof was accepted',
                subtitle: 'First to 10 Books',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleNotice extends StatelessWidget {
  const _SampleNotice({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      width: 300,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: c.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: c.ink,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: c.inkMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
