import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_dark_card.dart';

/// Proof screen — standalone (has own Scaffold, outside ShellRoute).
/// "Proof, not promises." — AI rep-counting verification.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with SingleTickerProviderStateMixin {
  _ProofState _state = _ProofState.idle;
  int _repCount = 0;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _startProof() {
    setState(() {
      _state = _ProofState.scanning;
      _repCount = 0;
    });
    _simulateReps();
  }

  Future<void> _simulateReps() async {
    for (var i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _state != _ProofState.scanning) return;
      setState(() => _repCount = i);
    }
    if (!mounted) return;
    setState(() => _state = _ProofState.success);
    _pulse.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: _state == _ProofState.success
          ? _SuccessView(
              pulse: _pulse,
              onBack: () => context.go('/arena'),
            )
          : SafeArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    20, topPad + 8, 20, bottomPad + 32),
                children: [
                  // Back button + title
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/arena'),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: NuvoColors.sectionBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: NuvoColors.border),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              size: 18, color: NuvoColors.navy),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Proof', style: AppTextStyles.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Hero text
                  Text(
                    'Proof, not promises.',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: NuvoColors.navy,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nuvo verifies your progress so winning actually means something.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: NuvoColors.muted),
                  ),
                  const SizedBox(height: 24),

                  // Scanner card (dark navy)
                  NuvoDarkCard(
                    child: Column(
                      children: [
                        // Camera frame
                        _ScannerFrame(
                            active: _state == _ProofState.scanning),
                        const SizedBox(height: 20),

                        // Status pill
                        _StatusPill(state: _state, repCount: _repCount),

                        const SizedBox(height: 16),

                        // Metrics row
                        const _MetricsRow(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Caption
                  Text(
                    _state == _ProofState.idle
                        ? 'Position yourself in frame and tap Start proof.'
                        : 'AI is counting your reps…',
                    textAlign: TextAlign.center,
                    style:
                        AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
                  ),
                  const SizedBox(height: 24),

                  if (_state == _ProofState.idle)
                    NuvoPrimaryButton(
                      label: 'Start proof',
                      icon: Icons.play_arrow_rounded,
                      expand: true,
                      onPressed: _startProof,
                    ),
                ],
              ),
            ),
    );
  }
}

enum _ProofState { idle, scanning, success }

// ---------------------------------------------------------------------------
// Scanner frame with corner brackets
// ---------------------------------------------------------------------------

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF040D1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_enhance_rounded,
                  size: 56,
                  color: NuvoColors.blue.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 8),
                Text(
                  'Camera preview',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: NuvoColors.muted),
                ),
              ],
            ),
          ),
          CustomPaint(
            painter: _CornerPainter(
              color: active ? NuvoColors.blue : NuvoColors.navySoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color});
  final Color color;

  static const _size = 20.0;
  static const _stroke = 2.5;
  static const _margin = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final l = _margin;
    final t = _margin;
    final r = size.width - _margin;
    final b = size.height - _margin;

    canvas
      // TL
      ..drawLine(Offset(l, t + _size), Offset(l, t), paint)
      ..drawLine(Offset(l, t), Offset(l + _size, t), paint)
      // TR
      ..drawLine(Offset(r - _size, t), Offset(r, t), paint)
      ..drawLine(Offset(r, t), Offset(r, t + _size), paint)
      // BL
      ..drawLine(Offset(l, b - _size), Offset(l, b), paint)
      ..drawLine(Offset(l, b), Offset(l + _size, b), paint)
      // BR
      ..drawLine(Offset(r - _size, b), Offset(r, b), paint)
      ..drawLine(Offset(r, b), Offset(r, b - _size), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Status pill
// ---------------------------------------------------------------------------

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.repCount});
  final _ProofState state;
  final int repCount;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      _ProofState.idle => 'AI check-in ready',
      _ProofState.scanning => 'Reps counted: $repCount / 100',
      _ProofState.success => 'Proof verified',
    };
    final color = state == _ProofState.scanning ? NuvoColors.blue : NuvoColors.mint;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics row
// ---------------------------------------------------------------------------

class _MetricsRow extends StatelessWidget {
  const _MetricsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Metric(value: '—', label: 'Reps tracked'),
        _Metric(value: '—', label: 'Form score'),
        _Metric(value: '—', label: 'Progress'),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.white),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Success view
// ---------------------------------------------------------------------------

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.pulse, required this.onBack});
  final AnimationController pulse;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(pulse.value);
        return Container(
          color: NuvoColors.white,
          padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPad + 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: 0.96 + 0.06 * t,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NuvoColors.mint.withValues(alpha: 0.12),
                    border: Border.all(color: NuvoColors.mint, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_rounded,
                      color: NuvoColors.mint, size: 48),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Proof verified',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: NuvoColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leaderboard updated.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.mint,
                ),
              ),
              const SizedBox(height: 40),
              NuvoPrimaryButton(
                label: 'Back to races',
                icon: Icons.arrow_forward_rounded,
                onPressed: onBack,
              ),
            ],
          ),
        );
      },
    );
  }
}
