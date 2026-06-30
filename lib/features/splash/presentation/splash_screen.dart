import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/presentation/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Signed-in users see a brief logo flash then continue immediately.
  bool _shortDelayDone = false;
  // Signed-out users wait for the full animation before reaching auth.
  bool _longDelayDone = false;
  bool _navigated = false;

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
    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      _shortDelayDone = true;
      _tryNavigate();
    });
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      _longDelayDone = true;
      _tryNavigate();
    });
  }

  void _tryNavigate() {
    if (_navigated || !_shortDelayDone) return;
    final authState = ref.read(authControllerProvider);
    if (authState.status == AuthStatus.loading) return;

    final isAuthenticated = authState.user != null;
    // Force signed-out users through the full animation.
    if (!isAuthenticated && !_longDelayDone) return;

    _navigated = true;
    final user = authState.user;
    if (user != null) {
      context.go(
        user.onboardingComplete ? '/arena' : '/onboarding/create-identity',
      );
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
      backgroundColor: NuvoColors.page,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [NuvoColors.white, NuvoColors.page, NuvoColors.icyBlue],
          ),
        ),
        child: Stack(
          children: [
            const _DotField(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with royal-blue glow
                  Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: NuvoColors.blue.withValues(alpha: 0.24),
                              blurRadius: 64,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Image.asset(AssetPaths.nuvoLogo),
                      )
                      .animate()
                      .fadeIn(duration: 620.ms, curve: Curves.easeOut)
                      .scale(
                        begin: const Offset(0.80, 0.80),
                        end: const Offset(1.0, 1.0),
                        duration: 700.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const SizedBox(height: 26),

                  Text(
                        'NUVO',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: NuvoColors.navy,
                          letterSpacing: 0,
                        ),
                      )
                      .animate(delay: 380.ms)
                      .fadeIn(duration: 360.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.14,
                        end: 0,
                        duration: 400.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const SizedBox(height: 8),

                  Text(
                        'Compete on anything. With anyone.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                        textAlign: TextAlign.center,
                      )
                      .animate(delay: 540.ms)
                      .fadeIn(duration: 360.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.14,
                        end: 0,
                        duration: 400.ms,
                        curve: Curves.easeOutCubic,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotField extends StatelessWidget {
  const _DotField();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(painter: _DotPainter()),
    );
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final paint = Paint()..color = NuvoColors.blue.withValues(alpha: 0.12);
    for (var i = 0; i < 42; i++) {
      final x = (i * 73) % size.width;
      final y = (i * 131) % size.height;
      if (x.isNaN || y.isNaN) continue;
      canvas.drawCircle(Offset(x, y), i.isEven ? 1.6 : 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
