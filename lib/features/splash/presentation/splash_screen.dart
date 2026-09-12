import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  static const int _frameCount = AssetPaths.splashFrameCount;
  static const int _fps = 60;
  static const Color _bg = NuvoColors.page;

  late final AnimationController _frameController;
  late final AnimationController _settleController;
  late final AnimationController _ambientController;
  bool _animationDone = false;
  bool _navigated = false;
  bool _continueRequested = false;
  bool _framesPrecached = false;
  bool _showOfflineRetry = false;
  Timer? _autoContinueTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    _frameController =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (_frameCount * 1000 / _fps).round()),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _settleController.forward();
          }
        });
    _settleController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _animationDone = true;
            if (mounted) setState(() {});
            _startAutoContinueTimer();
            _tryNavigate();
          }
        });
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _startSequence());
  }

  Future<void> _startSequence() async {
    if (!mounted) return;
    final bundle = DefaultAssetBundle.of(context);
    final warm = _frameCount < 12 ? _frameCount : 12;
    await Future.wait([
      for (var i = 0; i < warm; i++)
        precacheImage(
          AssetImage(AssetPaths.splashFrame(i), bundle: bundle),
          context,
        ),
      precacheImage(const AssetImage('assets/branding/nuvotext.png'), context),
    ]);
    if (!mounted) return;
    setState(() => _framesPrecached = true);
    _frameController.forward();
    Future(() async {
      for (var i = warm; i < _frameCount; i++) {
        if (!mounted) return;
        await precacheImage(
          AssetImage(AssetPaths.splashFrame(i), bundle: bundle),
          context,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoContinueTimer?.cancel();
    _frameController.dispose();
    _settleController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _startAutoContinueTimer() {
    _autoContinueTimer?.cancel();
    _autoContinueTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _navigated || _continueRequested) return;
      final authState = ref.read(authControllerProvider);
      if (authState.status == AuthStatus.loading) return;
      // The splash always advances on its own once auth resolves. Tapping is
      // still allowed as a shortcut, but nothing waits on it.
      _continue();
    });
  }

  Future<void> _tryNavigate() async {
    if (_navigated || !_animationDone || !_continueRequested) return;
    final authState = ref.read(authControllerProvider);
    if (authState.status == AuthStatus.loading) return;

    // Held tokens, but the server was unreachable on launch. Do not navigate
    // and do not log out — show the retry affordance.
    if (authState.status == AuthStatus.offline) {
      if (mounted && !_showOfflineRetry) setState(() => _showOfflineRetry = true);
      return;
    }
    if (_showOfflineRetry && mounted) setState(() => _showOfflineRetry = false);

    final user = authState.user;
    if (user != null && isNuvoStoreDemoEmail(user.email)) {
      // testing@getnuvo.net must always start fresh from the splash screen
      // and walk through the full first-launch flow.
      await ref.read(authControllerProvider.notifier).logout();
      return;
    }

    _navigated = true;
    if (user != null) {
      if (user.isDemo ||
          ref.read(demoReplayProvider) ||
          authState.guideFirstRace) {
        ref.read(demoReplayProvider.notifier).state = true;
        context.go('/welcome/intro');
        return;
      }
      // Router redirect (auth_gate) owns onboarding / first-race routing; go to
      // the app entry and let it place the user identically for every provider.
      context.go('/arena');
    } else {
      context.go('/welcome/intro');
    }
  }

  void _continue() {
    if (!_animationDone) return;
    setState(() => _continueRequested = true);
    _tryNavigate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.loading) {
        if (_animationDone) _startAutoContinueTimer();
        _tryNavigate();
      }
    });

    return Scaffold(
      backgroundColor: _bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _continue,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _frameController,
            _settleController,
            _ambientController,
          ]),
          builder: (context, _) => CustomPaint(
            painter: _LaunchAtmospherePainter(
              progress: _ambientController.value,
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: _framesPrecached
                        ? _LaunchMark(
                            frameProgress: _frameController.value,
                            settleProgress: Curves.easeOutCubic.transform(
                              _settleController.value,
                            ),
                          )
                        : const SizedBox(width: 280, height: 280),
                  ),
                  if (_showOfflineRetry)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                        child: _OfflineRetry(
                          onRetry: () {
                            setState(() {
                              _showOfflineRetry = false;
                              _navigated = false;
                            });
                            ref
                                .read(authControllerProvider.notifier)
                                .retryRestore();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchMark extends StatelessWidget {
  const _LaunchMark({
    required this.frameProgress,
    required this.settleProgress,
  });

  final double frameProgress;
  final double settleProgress;

  @override
  Widget build(BuildContext context) {
    final frame = (frameProgress * (SplashScreenStateAccess.frameCount - 1))
        .round()
        .clamp(0, SplashScreenStateAccess.frameCount - 1);
    final imageSize = Tween<double>(
      begin: 280,
      end: 180,
    ).transform(settleProgress);
    final markLift = Tween<double>(
      begin: 0,
      end: -72,
    ).transform(settleProgress);
    final wordmarkReveal = Curves.easeOutCubic.transform(
      ((settleProgress - .28) / .72).clamp(0, 1),
    );

    return Transform.translate(
      offset: Offset(0, markLift),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            AssetPaths.splashFrame(frame),
            width: imageSize,
            height: imageSize,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
          Opacity(
            opacity: settleProgress,
            child: Column(
              children: [
                const Text(
                  'WELCOME TO',
                  style: TextStyle(
                    color: NuvoColors.blue,
                    fontFamily: 'Avenir Next',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.1,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: 42,
                  height: 3,
                  decoration: BoxDecoration(
                    color: NuvoColors.blue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: wordmarkReveal,
              child: Image.asset(
                'assets/branding/nuvotext.png',
                width: 210,
                height: 59,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SplashScreenStateAccess {
  static const frameCount = AssetPaths.splashFrameCount;
}

/// Shown on the splash when the app holds a saved session but could not reach
/// the server on launch. The user is still signed in — this only offers a
/// retry, it never routes to sign-in.
class _OfflineRetry extends StatelessWidget {
  const _OfflineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Couldn't reach Nuvo",
          style: AppTextStyles.titleMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 4),
        Text(
          'Check your connection — you are still signed in.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        NuvoPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          expand: true,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _LaunchAtmospherePainter extends CustomPainter {
  const _LaunchAtmospherePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * math.pi * 2;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = NuvoColors.page);

    // Give the white mark a quiet contrast pocket without introducing a hard
    // badge or circle behind it. One hue (brand blue) at falling alpha, per
    // the design guide — no second palette for the glow effect.
    final markCenter = Offset(size.width / 2, size.height * .43);
    final markField = Rect.fromCenter(
      center: markCenter,
      width: size.width * .66,
      height: size.height * .34,
    );
    canvas.drawOval(
      markField,
      Paint()
        ..shader = RadialGradient(
          colors: [
            NuvoColors.blue.withValues(alpha: .27),
            NuvoColors.blue.withValues(alpha: .13),
            NuvoColors.blue.withValues(alpha: 0),
          ],
          stops: const [0, .45, 1],
        ).createShader(markField),
    );

    // The whole matrix stays present. Broad overlapping waves make every
    // region breathe instead of isolating the animation to a few dots.
    const columns = 18;
    const rows = 31;
    final spacingX = size.width / (columns + 1);
    final spacingY = size.height / (rows + 1);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = spacingX * (column + 1);
        final y = spacingY * (row + 1);
        final nx = column / (columns - 1);
        final ny = row / (rows - 1);
        final centerDistance = math.sqrt(
          math.pow(nx - .5, 2) + math.pow(ny - .46, 2),
        );
        final diagonal = nx * .9 + ny * 1.1;
        final expandingRing = math.sin(t * 2.8 - centerDistance * 20.0);
        final counterRing = math.sin(t * 2.2 - (1 - centerDistance) * 17.0);
        final diagonalBurst = math.sin(t * 2.1 - diagonal * 11.0);
        final pulse =
            (((expandingRing + 1) * .48) +
                    ((counterRing + 1) * .30) +
                    ((diagonalBurst + 1) * .22))
                .clamp(0.0, 1.0)
                .toDouble();
        final quietZone = centerDistance < .13 ? .40 : 1.0;
        final radius =
            (.45 + Curves.easeOut.transform(pulse) * 2.45) * quietZone;
        dotPaint.color = Color.lerp(
          NuvoColors.blueLight.withValues(alpha: .20),
          NuvoColors.blue.withValues(alpha: .68),
          pulse,
        )!;
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LaunchAtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
