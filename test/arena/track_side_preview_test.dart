import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_text_styles.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/nuvo_avatar.dart';
import 'package:nuvo/core/widgets/track_side_orbit.dart';

void main() {
  testWidgets('TrackSide preview renders at 390x844', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            devicePixelRatio: 1.0,
            disableAnimations: true,
          ),
          child: _TrackSidePreview(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(_TrackSidePreview),
      matchesGoldenFile('goldens/track_side_preview.png'),
    );
  }, skip: true);
}

const _kNavy = Color(0xFF071B35);
const _kBlue = Color(0xFF2F7CFF);
const _kWhite = Color(0xFFF8FAFD);
const _kMuted = Color(0xFFC5CBD5);
const _kWarmWhite = Color(0xFFFAF9F6);
const _kDarkText = Color(0xFF152238);
const _kMutedText = Color(0xFF7F8795);
const _kSeparator = Color(0xFFDDE1E6);
const _kDarkProgress = Color(0xFF414A59);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return parts.isNotEmpty && parts[0].isNotEmpty
      ? parts[0][0].toUpperCase()
      : '?';
}

class _TrackSidePreview extends StatelessWidget {
  const _TrackSidePreview();

  @override
  Widget build(BuildContext context) {
    const scale = 1.0;
    const totalGoal = 100;
    const currentValue = 65;

    const participants = [
      TrackSideOrbitParticipant(
        id: 'me',
        name: 'You',
        initials: 'YO',
        rank: 1,
        progressValue: 65,
        isCurrentUser: true,
      ),
      TrackSideOrbitParticipant(
        id: 'alex',
        name: 'Alex R.',
        initials: 'AR',
        rank: 2,
        progressValue: 48,
      ),
      TrackSideOrbitParticipant(
        id: 'maya',
        name: 'Maya L.',
        initials: 'ML',
        rank: 3,
        progressValue: 31,
      ),
    ];

    return Scaffold(
      backgroundColor: _kNavy,
      body: Column(
        children: [
          SizedBox(
            height: 464 * scale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: _kNavy,
                    gradient: RadialGradient(
                      center: Alignment(1.2, -0.8),
                      radius: 0.8,
                      colors: [Color(0xFF0E2E5C), _kNavy],
                      stops: [0.0, 0.9],
                    ),
                  ),
                ),
                Positioned(
                  left: 26 * scale,
                  top: 31 * scale,
                  child: Image.asset(
                    'assets/branding/nuvo_logo.png',
                    height: 24 * scale,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 24),
                  ),
                ),
                Positioned(
                  right: 26 * scale,
                  top: 31 * scale,
                  child: Text(
                    'ARENA',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _kBlue,
                      fontSize: 12 * scale,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 83 * scale,
                  child: Text(
                    'Your next move',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: _kWhite,
                      fontSize: 28 * scale,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 119 * scale,
                  child: Text(
                    'First to $totalGoal Pushups',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _kMuted,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 155 * scale,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$currentValue',
                        style: AppTextStyles.displayLarge.copyWith(
                          color: _kBlue,
                          fontSize: 64 * scale,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        ' / ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _kMuted,
                          fontSize: 24 * scale,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        '$totalGoal',
                        style: AppTextStyles.displayLarge.copyWith(
                          color: _kWhite,
                          fontSize: 56 * scale,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 234 * scale,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '35',
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: _kBlue,
                            fontSize: 15 * scale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' to the finish line',
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: _kMuted,
                            fontSize: 15 * scale,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Positioned(
                  left: 22 * scale,
                  top: 176 * scale,
                  child: TrackSideOrbit(
                    scale: scale,
                    totalGoal: totalGoal,
                    currentUserValue: currentValue,
                    currentUserRank: 1,
                    participants: participants,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 389 * scale,
                  child: Center(
                    child: Container(
                      width: 241 * scale,
                      height: 51 * scale,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8 * scale),
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xFF1A63D8), _kBlue],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Submit proof',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: _kWhite,
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: _kWarmWhite,
              padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'CREW STANDINGS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: _kMutedText,
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'VIEW ALL',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: _kBlue,
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _StandingRow(
                    rank: 1,
                    label: 'You',
                    value: '65 / 100',
                    isUser: true,
                  ),
                  const Divider(height: 20, thickness: 0.5, color: _kSeparator),
                  const _StandingRow(
                    rank: 2,
                    label: 'Alex R.',
                    value: '48 / 100',
                  ),
                  const Divider(height: 20, thickness: 0.5, color: _kSeparator),
                  const _StandingRow(
                    rank: 3,
                    label: 'Maya L.',
                    value: '31 / 100',
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'RECENT ACTIVITY',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _kMutedText,
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NuvoAvatar(
                        initials: 'ML',
                        size: 28,
                        bgColor: nuvoAvatarColorFor('Maya L.'),
                        textColor: _kWhite,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Maya L.',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: _kDarkText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: ' submitted 20 pushups',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: _kMutedText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        '2m ago',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _kMutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          NuvoBottomNav(
            currentIndex: 0,
            onTap: (_) {},
            isDark: true,
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.label,
    required this.value,
    this.isUser = false,
  });

  final int rank;
  final String label;
  final String value;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final parts = value.split('/').map((s) => s.trim()).toList();
    final valueNum = int.tryParse(parts.first) ?? 0;
    final totalNum = parts.length > 1 ? int.tryParse(parts[1]) ?? 100 : 100;
    final progress = totalNum == 0 ? 0.0 : valueNum / totalNum;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: isUser
                ? Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: _kBlue,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _kWhite,
                      ),
                    ),
                  )
                : Text(
                    '$rank',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _kMutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          NuvoAvatar(
            initials: _initials(label),
            size: 36,
            bgColor: nuvoAvatarColorFor(label),
            textColor: _kWhite,
            borderColor: isUser ? _kBlue : NuvoColors.white,
            borderWidth: isUser ? 2.0 : 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isUser ? _kBlue : _kDarkText,
                fontSize: 15,
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isUser ? _kBlue : _kMutedText,
              fontSize: 14,
              fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: 70,
              height: 6,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _kSeparator,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isUser ? _kBlue : _kDarkProgress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
