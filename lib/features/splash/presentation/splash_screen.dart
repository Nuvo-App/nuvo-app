import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
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
  bool _animationDone = false;
  bool _navigated = false;
  bool _continueRequested = false;
  bool _framesPrecached = false;
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

    // Held tokens, but the server was unreachable on launch. Do not log the
    // user out — finish the splash and let Arena own the in-page
    // "no connection" / retry experience (with its normal header and nav),
    // instead of stranding the user on a permanent splash error page.
    if (authState.status == AuthStatus.offline) {
      _navigated = true;
      context.go('/arena');
      return;
    }

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
          animation: Listenable.merge([_frameController, _settleController]),
          builder: (context, _) => CustomPaint(
            painter: const _LaunchAtmospherePainter(),
            child: SafeArea(
              child: Center(
                child: _framesPrecached
                    ? _LaunchMark(
                        frameProgress: _frameController.value,
                        settleProgress: Curves.easeOutCubic.transform(
                          _settleController.value,
                        ),
                      )
                    : const SizedBox(width: 280, height: 280),
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

/// One quiet static blue glow behind the mark — no ambient dot-grid loop.
/// The loading screen's job is to feel focused and branded (the mark/frame
/// animation and the wordmark reveal already carry that), not busy; a large
/// animated field of ~550 pulsing dots was competing with the brand moment
/// for attention rather than supporting it.
class _LaunchAtmospherePainter extends CustomPainter {
  const _LaunchAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
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
  }

  @override
  bool shouldRepaint(covariant _LaunchAtmospherePainter oldDelegate) => false;
}
