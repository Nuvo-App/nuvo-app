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
import '../data/race_models.dart';
import 'race_controller.dart';

class InviteCrewScreen extends ConsumerStatefulWidget {
  const InviteCrewScreen({super.key, required this.raceId});

  final String raceId;

  @override
  ConsumerState<InviteCrewScreen> createState() => _InviteCrewScreenState();
}

class _InviteCrewScreenState extends ConsumerState<InviteCrewScreen> {
  Race? _race;
  String? _inviteCode;
  String? _error;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.raceId);
      if (mounted) {
        setState(() {
          _race = race;
          _inviteCode = race.inviteCode;
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NuvoIconAction(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to race',
                        onPressed: () =>
                            safePopOrGo(context, '/race/${widget.raceId}'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Invite crew', style: AppTextStyles.headlineLarge),
                    const SizedBox(height: 8),
                    Text(
                      _race!.title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: NuvoColors.navy,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3307152B),
                            blurRadius: 0,
                            offset: Offset(6, 7),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INVITE CODE',
                            style: AppTextStyles.brandLabel.copyWith(
                              color: NuvoColors.softBlue,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _inviteCode ?? 'Create a code',
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: NuvoColors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Direct race links are coming soon. For now, your crew can open Nuvo and enter this code.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: NuvoColors.softBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
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
                        label: 'Copy invite code',
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
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text('Crew', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: NuvoColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: NuvoColors.border),
                      ),
                      child: Text(
                        'Your crew is waiting at the start line. Invite people with a code until direct race links are ready.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}
