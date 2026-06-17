import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _fadeInCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();

    // Light icons on the dark gradient background.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _fadeInCtrl, curve: Curves.easeOut);

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      context.go('/auth/phone');
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fadeInCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold background is the darkest gradient stop so iOS sees dark even
    // before the gradient Container paints (avoids white flash at launch).
    return Scaffold(
      backgroundColor: const Color(0xFF06142B),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF06142B),
              Color(0xFF0A2A66),
              Color(0xFF2F73EA),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            // Only the content fades in — the dark background is always visible.
            opacity: _fadeIn,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(_pulse.value);
                    return Transform.scale(
                      scale: 0.97 + 0.06 * t,
                      child: _LogoMark(glowOpacity: 0.15 + 0.20 * t),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'nuvo',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: Colors.white,
                    letterSpacing: -1.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Compete on anything. With anyone.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.glowOpacity});
  final double glowOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: glowOpacity),
            blurRadius: 50,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: glowOpacity * 0.7),
            blurRadius: 80,
            spreadRadius: 20,
          ),
        ],
      ),
      child: Image.asset(
        AssetPaths.nuvoLogo,
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.bolt_rounded,
            size: 60,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
