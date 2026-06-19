import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/member_pass_card.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../data/models/user_profile.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';

class PassScreen extends ConsumerStatefulWidget {
  const PassScreen({super.key});

  @override
  ConsumerState<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends ConsumerState<PassScreen> {
  PassInfo? _passInfo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPass();
  }

  Future<void> _fetchPass() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pass = await ref
          .read(authControllerProvider.notifier)
          .getMemberPass();
      if (mounted) {
        setState(() {
          _passInfo = pass;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your member pass.';
          _loading = false;
        });
      }
    }
  }

  UserProfile _buildProfile(AuthUser? user) {
    return UserProfile(
      name: user?.fullName ?? user?.email ?? '',
      username: user?.username ?? '',
      memberId: _passInfo?.memberId ?? '—',
      passSlug: _passInfo?.passSlug,
    );
  }

  void _showQrComingSoonSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NuvoColors.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Icon(
                Icons.qr_code_scanner_rounded,
                color: NuvoColors.blue,
                size: 44,
              ),
              const SizedBox(height: 16),
              Text(
                'QR scanning coming soon',
                style: AppTextStyles.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Share your member pass link with crew instead.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = _buildProfile(user);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text('Your Pass', style: AppTextStyles.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'Share your member ID and pull in your crew.',
            style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            NuvoErrorState(message: _error!, onRetry: _fetchPass)
          else
            MemberPassCard(profile: profile, compact: true),
          const SizedBox(height: 18),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search username or member ID',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                onPressed: () => _showQrComingSoonSheet(context),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Crew', style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          const NuvoEmptyState(
            icon: Icons.group_add_rounded,
            title: 'Your crew is waiting at the start line.',
            body: 'Invite friends to turn this into a race.',
          ),
        ],
      ),
    );
  }
}
