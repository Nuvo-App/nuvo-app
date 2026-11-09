import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_face.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../social/social_providers.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import 'level_share_card.dart';
import 'onboarding_reward.dart';

/// S15 — LEVEL UP, the one full-bleed Nuvo blue screen (spec §S15).
///
/// One linear timeline ([NuvoMotion.levelUpTotal]) drives every beat:
/// scrim to blue, avatar rises (ring 96%), ring fills with ticks, flash +
/// shockwave + confetti + heavy haptic + fanfare, LEVEL 1 rolls to LEVEL 2,
/// "LEVEL UP" letters drop in, three reward tiles slide up, the CTA rises.
/// Tap anywhere after [NuvoMotion.levelUpSkipAfter] speeds to the CTA. The
/// reward numbers are the server's (`POST /onboarding/complete`), fetched
/// when the step mounts; spec constants stand in only if that call fails.
class ObLevelUpStep extends ConsumerStatefulWidget {
  const ObLevelUpStep({super.key});

  @override
  ConsumerState<ObLevelUpStep> createState() => _ObLevelUpStepState();
}

class _ObLevelUpStepState extends ConsumerState<ObLevelUpStep>
    with TickerProviderStateMixin {
  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: NuvoMotion.levelUpTotal,
  );
  late final AnimationController _flood = AnimationController(
    vsync: this,
    duration: NuvoMotion.levelUpFlood,
  );
  final GlobalKey _ctaKey = GlobalKey();
  final GlobalKey _cardKey = GlobalKey();

  bool _busy = false;
  bool _failed = false;
  bool _shareFailed = false;
  bool _sharing = false;
  String? _shareUrl;
  bool _skipping = false;

  int _ticks = 0;
  bool _flashed = false;
  bool _successFired = false;
  int _tilesFired = 0;
  bool _started = false;


  @override
  void initState() {
    super.initState();
    _timeline.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _timeline.value = 1;
      _fireFlash();
    } else {
      _timeline.forward();
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    _flood.dispose();
    super.dispose();
  }

  double get _ms => _timeline.value * NuvoMotion.levelUpTotal.inMilliseconds;

  /// 0..1 progress of the segment [at, at+dur] on the timeline.
  double _seg(Duration at, Duration dur, [Curve? curve]) {
    final t = ((_ms - at.inMilliseconds) / dur.inMilliseconds).clamp(0.0, 1.0);
    return curve == null ? t : curve.transform(t);
  }

  void _fireFlash() {
    if (_flashed) return;
    _flashed = true;
    ref.read(onboardingFlowProvider.notifier).levelUpSeen();
  }

  void _onTick() {
    final ms = _ms;
    final fillT = _seg(NuvoMotion.levelUpFillAt, NuvoMotion.levelUpFill);
    final ticks = (fillT * NuvoMotion.levelUpFillTicks).floor();
    if (ticks > _ticks) {
      _ticks = ticks;
      if (!_skipping) NuvoHaptics.select();
    }
    if (ms >= NuvoMotion.levelUpFlashAt.inMilliseconds) _fireFlash();
    if (!_successFired && ms >= NuvoMotion.levelUpLettersAt.inMilliseconds) {
      _successFired = true;
      if (!_skipping) NuvoHaptics.success();
    }
    while (_tilesFired < 3 &&
        ms >=
            NuvoMotion.levelUpTilesAt.inMilliseconds +
                _tilesFired * NuvoMotion.staggerStep.inMilliseconds) {
      _tilesFired++;
      if (!_skipping) NuvoHaptics.light();
    }
    setState(() {});
  }

  void _onScreenTap() {
    if (_timeline.value >= 1 || _busy) return;
    if (_ms < NuvoMotion.levelUpSkipAfter.inMilliseconds) return;
    _skipping = true;
    _timeline.animateTo(1, duration: NuvoMotion.levelUpSkipRun);
  }

  Future<void> _enter() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    if (NuvoMotion.reduceMotionOf(context)) {
      _flood.value = 1;
    } else {
      await _flood.forward();
    }
    if (!mounted) return;
    final ok = await ref.read(onboardingFlowProvider.notifier).graduate();
    if (!mounted) return;
    if (!ok) {
      await _flood.reverse();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
    // ok → the host's readyToGraduate listen performs context.go('/arena').
  }

  Future<void> _share(OnboardingReward reward) async {
    if (_sharing) return;
    setState(() {
      _sharing = true;
      _shareFailed = false;
    });
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .mintMyCrewInvite();
      if (!mounted) return;
      setState(() => _shareUrl = invite.url);
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final png = await captureLevelShareCard(_cardKey);
      if (png == null || !mounted) throw StateError('no card');
      final box = context.findRenderObject() as RenderBox?;
      await shareLevelPng(
        png,
        origin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      if (mounted) setState(() => _shareFailed = true);
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
          _shareUrl = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reward =
        ref.watch(onboardingRewardProvider).valueOrNull ??
        OnboardingReward.fallback;
    final user = ref.watch(authControllerProvider).user;
    final size = MediaQuery.sizeOf(context);

    final scrim = _seg(
      Duration.zero,
      NuvoMotion.levelUpScrim,
      NuvoMotion.levelUpScrimCurve,
    );
    final avatarT = _seg(
      NuvoMotion.levelUpAvatarAt,
      NuvoMotion.springDuration,
      NuvoMotion.spring,
    );
    final fillT = _seg(
      NuvoMotion.levelUpFillAt,
      NuvoMotion.levelUpFill,
      NuvoMotion.levelUpFillCurve,
    );
    final ringValue =
        NuvoMotion.levelUpRingStart + (1 - NuvoMotion.levelUpRingStart) * fillT;
    final shockT = _seg(
      NuvoMotion.levelUpFlashAt,
      NuvoMotion.levelUpShockwave,
      NuvoMotion.levelUpShockwaveCurve,
    );
    final confettiT = _seg(NuvoMotion.levelUpFlashAt, NuvoMotion.confetti);
    final rolled = _ms >= NuvoMotion.levelUpNumberAt.inMilliseconds;
    final ctaT = _seg(
      NuvoMotion.levelUpCtaAt,
      NuvoMotion.springDuration,
      NuvoMotion.spring,
    );
    final ctaReady = _timeline.value >= 1;
    final name = user?.fullName ?? user?.username ?? 'You';

    final tiles = <(IconData, String)>[
      (Icons.bolt_rounded, reward.xpTile),
      (Icons.military_tech_rounded, reward.badgeName),
      (Icons.local_fire_department_rounded, reward.streakTile),
    ];

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onScreenTap,
      child: ColoredBox(
        color: Color.lerp(V13.bg, V13.blue, scrim)!,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  Opacity(
                    opacity: avatarT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - avatarT) * 140),
                      child: SizedBox(
                        width: 188,
                        height: 188,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            if (shockT > 0 && shockT < 1)
                              Opacity(
                                opacity: 1 - shockT,
                                child: Transform.scale(
                                  scale:
                                      1 +
                                      (NuvoMotion.levelUpShockwaveScale - 1) *
                                          shockT,
                                  child: Container(
                                    width: 172,
                                    height: 172,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: V13.white,
                                        width: V13.outlineThick,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            CustomPaint(
                              size: const Size.square(172),
                              painter: _RingPainter(
                                value: ringValue,
                                flash: _flashed && shockT < 1,
                              ),
                            ),
                            // No photo → big initials, never a blank disc.
                            if ((user?.profilePhotoUrl ?? '').isNotEmpty)
                              V13Face(
                                photoUrl: user?.profilePhotoUrl,
                                size: 140,
                                name: name,
                              )
                            else
                              Container(
                                width: 140,
                                height: 140,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: V13.navy,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: V13.white,
                                    width: V13.outlineThick,
                                  ),
                                ),
                                child: Text(
                                  _initials(name),
                                  style: V13.hugeNumber.copyWith(
                                    fontSize: 52,
                                    color: V13.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: V13.gapXl),
                  Opacity(
                    opacity: avatarT,
                    child: NuvoNumberFlow(
                      value: rolled ? reward.toLevel : reward.fromLevel,
                      format: (v) => 'LEVEL $v',
                      duration: NuvoMotion.levelUpNumber,
                      style: V13.hugeNumber.copyWith(
                        fontSize: 56,
                        color: V13.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: V13.gapXl),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V13.pagePad,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) const SizedBox(width: V13.gapMd),
                            Expanded(
                              child: _RewardTile(
                                icon: tiles[i].$1,
                                label: tiles[i].$2,
                                t: _seg(
                                  NuvoMotion.levelUpTilesAt +
                                      NuvoMotion.staggerStep * i,
                                  NuvoMotion.springDuration,
                                  NuvoMotion.spring,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Opacity(
                    opacity: ctaT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - ctaT) * 60),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_failed || _shareFailed) ...[
                              _InlineError(
                                _failed ? ObCopy.genericRetry : _shareError,
                              ),
                              const SizedBox(height: V13.gapMd),
                            ],
                            NuvoPressable(
                              key: _ctaKey,
                              enabled: ctaReady && !_busy,
                              onTap: ctaReady && !_busy ? _enter : null,
                              borderRadius: BorderRadius.circular(
                                V13.radiusButton,
                              ),
                              shadow: V13.shadow4,
                              semanticLabel: ObCopy.levelUpCta,
                              child: Container(
                                key: const ValueKey('onboarding-cta'),
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: V13.white,
                                  borderRadius: BorderRadius.circular(
                                    V13.radiusButton,
                                  ),
                                  border: Border.all(
                                    color: V13.navy,
                                    width: V13.outlineThick,
                                  ),
                                ),
                                child: Text(
                                  ObCopy.levelUpCta,
                                  style: V13.buttonLabel,
                                ),
                              ),
                            ),
                            const SizedBox(height: V13.gapSm),
                            // Plain white link — a themed TextButton painted
                            // a grey pill that hid the label on blue.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: (_busy || _sharing || !ctaReady)
                                  ? null
                                  : () => _share(reward),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: V13.gapMd,
                                  horizontal: V13.gapLg,
                                ),
                                child: Text(
                                  ObCopy.levelUpShare,
                                  style: V13.bodyStrong.copyWith(
                                    color: V13.white,
                                    decoration: TextDecoration.underline,
                                    decorationColor: V13.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: V13.gapMd),
                ],
              ),
            ),
            if (confettiT > 0 && confettiT < 1)
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _ConfettiPainter(
                    progress: confettiT,
                    origin: Offset(size.width / 2, size.height * 0.30),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: V13.bg,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flood,
              builder: (context, child) {
                if (_flood.value == 0) return child!;
                return ClipPath(
                  clipper: _FloodClipper(
                    progress: _flood.value,
                    center: _ctaCenter(size),
                  ),
                  child: child,
                );
              },
              child: content,
            ),
          ),
          if (_shareUrl != null)
            Positioned(
              left: -(LevelShareCard.width + 200),
              top: 0,
              width: LevelShareCard.width,
              height: LevelShareCard.height,
              child: RepaintBoundary(
                key: _cardKey,
                child: LevelShareCard(
                  name: name,
                  level: reward.toLevel,
                  inviteUrl: _shareUrl!,
                  photoUrl: user?.profilePhotoUrl,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const String _shareError = 'Could not open share. Try again.';

  Offset _ctaCenter(Size size) {
    final box = _ctaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return Offset(size.width / 2, size.height - 120);
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.icon, required this.label, required this.t});

  final IconData icon;
  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 48),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: V13.gapMd,
            horizontal: V13.gapSm,
          ),
          decoration: BoxDecoration(
            color: V13.white,
            borderRadius: BorderRadius.circular(V13.radiusTileLg),
            border: Border.all(color: V13.navy, width: V13.outlineThick),
            boxShadow: V13.shadow4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: V13.blue, size: 28),
              const SizedBox(height: V13.gapXs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: V13.bodyStrong.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapMd,
        vertical: V13.gapSm,
      ),
      decoration: BoxDecoration(
        color: V13.white,
        borderRadius: BorderRadius.circular(V13.radiusTile),
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: V13.bodyStrong.copyWith(color: V13.danger),
      ),
    );
  }
}

/// White progress ring on a translucent track; [flash] thickens it for the
/// completion beat.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.flash});

  final double value;
  final bool flash;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = flash ? 12.0 : 9.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = V13.white.withValues(alpha: 0.28),
    );
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = V13.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.flash != flash;
}

/// White / sun / coral confetti burst from the avatar. Deterministic pieces
/// (seeded) so the burst reads the same every time.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.origin});

  final double progress;
  final Offset origin;

  static const _colors = [V13.white, V13.sun, V13.coral];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(15);
    final fade = (1 - progress).clamp(0.0, 1.0);
    for (var i = 0; i < NuvoMotion.confettiPieces; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 0.5 + rng.nextDouble() * 0.9;
      final spin = rng.nextDouble() * math.pi * 2;
      final w = 6 + rng.nextDouble() * 6;
      final dist = speed * size.width * 0.6 * progress;
      final gravity = 0.55 * size.height * progress * progress;
      final p =
          origin +
          Offset(
            math.cos(angle) * dist,
            math.sin(angle) * dist * 0.8 + gravity,
          );
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(spin + progress * 6);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

/// The flood: keeps everything OUTSIDE a growing circle, so the blue
/// recedes away from the CTA and reveals the page beneath.
class _FloodClipper extends CustomClipper<Path> {
  _FloodClipper({required this.progress, required this.center});

  final double progress;
  final Offset center;

  @override
  Path getClip(Size size) {
    final farthest = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addOval(Rect.fromCircle(center: center, radius: farthest * progress)),
    );
  }

  @override
  bool shouldReclip(_FloodClipper old) =>
      old.progress != progress || old.center != center;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'N';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.elementAt(1)[0]}'.toUpperCase();
}
