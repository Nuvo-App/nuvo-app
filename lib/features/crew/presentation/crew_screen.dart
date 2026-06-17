import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/friend_card.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_page.dart';

/// Crew screen — inside the bottom nav shell (no Scaffold).
class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key});

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};

  static const _crew = [
    CrewMember(
      id: 'jordan',
      name: 'Jordan Lee',
      username: 'jordanlee',
      activeRaces: 3,
      streak: 14,
    ),
    CrewMember(
      id: 'sam',
      name: 'Sam Rivera',
      username: 'samr',
      activeRaces: 1,
      streak: 7,
    ),
    CrewMember(
      id: 'mika',
      name: 'Mika Tanaka',
      username: 'mikatan',
      activeRaces: 2,
      streak: 21,
    ),
    CrewMember(
      id: 'alex',
      name: 'Alex Chen',
      username: 'alexc',
      activeRaces: 4,
      streak: 5,
    ),
    CrewMember(
      id: 'tay',
      name: 'Tay Williams',
      username: 'tayw',
      activeRaces: 0,
      streak: 3,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        // Top bar — "Your crew" title, no logo
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your crew', style: AppTextStyles.headlineMedium),
                const SizedBox(height: 2),
                Text(
                  'Add friends and start races together.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
            const Spacer(),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: NuvoColors.sectionBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_rounded,
                size: 18,
                color: NuvoColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Premium Member Pass card
        const _MemberPassCard(
          memberId: 'NUVO-AKSHAY-4821',
          name: 'Akshay Deepak',
          username: 'akshay',
          profileUrl: 'https://nuvothrive.netlify.app/u/akshay',
        ),
        const SizedBox(height: 24),

        // Add a friend
        const NuvoSectionHeader(title: 'Add a friend'),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          style: AppTextStyles.bodyMedium,
          decoration: const InputDecoration(
            hintText: 'Search by username or member ID',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAddButton(
                icon: Icons.contacts_rounded,
                label: 'From contacts',
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAddButton(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan QR',
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Crew list
        NuvoSectionHeader(
          title: 'Friends (${_crew.length})',
          onSeeAll: _selectedIds.isEmpty ? null : () {},
        ),
        const SizedBox(height: 12),

        ..._crew.map((member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FriendCard(
                member: member,
                selectable: true,
                selected: _selectedIds.contains(member.id),
                onTap: () => setState(() {
                  if (_selectedIds.contains(member.id)) {
                    _selectedIds.remove(member.id);
                  } else {
                    _selectedIds.add(member.id);
                  }
                }),
                onRace: () => context.go('/create'),
              ),
            )),

        if (_selectedIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          NuvoPrimaryButton(
            label: 'Start race with ${_selectedIds.length} '
                '${_selectedIds.length == 1 ? 'friend' : 'friends'}',
            icon: Icons.flag_rounded,
            expand: true,
            onPressed: () => context.go('/create'),
          ),
        ] else ...[
          const SizedBox(height: 8),
          NuvoSecondaryButton(
            label: 'Start a race with crew',
            icon: Icons.flag_rounded,
            expand: true,
            onPressed: () => context.go('/create'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium Member Pass card
// ---------------------------------------------------------------------------

class _MemberPassCard extends StatelessWidget {
  const _MemberPassCard({
    required this.memberId,
    required this.name,
    required this.username,
    required this.profileUrl,
  });

  final String memberId;
  final String name;
  final String username;
  final String profileUrl;

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: profileUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  void _share() {
    Share.share('Join me on nuvo: $profileUrl');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1048A0), Color(0xFF2F73EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Decorative diagonal highlight strip
          Positioned(
            top: -24,
            right: 52,
            child: Transform.rotate(
              angle: -0.45,
              child: Container(
                width: 48,
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pass header
                Row(
                  children: [
                    Text(
                      'MEMBER PASS',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'nuvo',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Name
                Text(
                  name,
                  style: AppTextStyles.headlineMedium
                      .copyWith(color: Colors.white),
                ),
                Text(
                  '@$username',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),

                // QR code on white background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: profileUrl,
                        version: QrVersions.auto,
                        size: 120,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        memberId,
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.navy,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  'Share this pass so friends can find and add you.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _PassActionButton(
                        icon: Icons.copy_rounded,
                        label: 'Copy link',
                        onTap: () => _copyLink(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PassActionButton(
                        icon: Icons.share_rounded,
                        label: 'Share',
                        onTap: _share,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fade(duration: 600.ms)
        .slideY(begin: 0.06, end: 0, duration: 600.ms, curve: Curves.easeOut)
        .shimmer(
          duration: 900.ms,
          delay: 350.ms,
          color: Colors.white.withValues(alpha: 0.3),
        );
  }
}

class _PassActionButton extends StatelessWidget {
  const _PassActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white30),
          color: Colors.white.withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium
                  .copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick add button
// ---------------------------------------------------------------------------

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: NuvoColors.sectionBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: NuvoColors.blue),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.blue),
            ),
          ],
        ),
      ),
    );
  }
}
