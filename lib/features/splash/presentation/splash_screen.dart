import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../auth/presentation/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const int _frameCount = AssetPaths.splashFrameCount;
  static const int _fps = 60;
  static const Color _bg = Color(0xFF07152C);

  late final AnimationController _controller;
  bool _animationDone = false;
  bool _navigated = false;
  bool _framesPrecached = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_frameCount * 1000 / _fps).round()),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationDone = true;
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
    ]);
    if (!mounted) return;
    setState(() => _framesPrecached = true);
    _controller.forward();
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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tryNavigate() async {
    if (_navigated || !_animationDone) return;
    final authState = ref.read(authControllerProvider);
    if (authState.status == AuthStatus.loading) return;

    _navigated = true;
    final user = authState.user;
    if (user != null) {
      if (user.onboardingComplete) {
        context.go('/arena');
        return;
      }
      await ref.read(authControllerProvider.notifier).sessionExpired();
      if (mounted) context.go('/welcome');
    } else {
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.loading) _tryNavigate();
    });

    return Scaffold(
      backgroundColor: _bg,
      body: ColoredBox(
        color: _bg,
        child: Center(
          child: _framesPrecached
              ? AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final frame = (_controller.value * (_frameCount - 1))
                        .round()
                        .clamp(0, _frameCount - 1);
                    return Image.asset(
                      AssetPaths.splashFrame(frame),
                      width: 280,
                      height: 280,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    );
                  },
                )
              : const SizedBox(width: 280, height: 280),
        ),
      ),
    );
  }
}
