import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/nuvo_preview_style.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

class PreviewStyleChooser extends StatelessWidget {
  const PreviewStyleChooser({super.key, required this.onSelected});

  final ValueChanged<NuvoPreviewStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 42,
                          child: ClipRect(
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF07152C),
                                BlendMode.srcIn,
                              ),
                              child: Transform.scale(
                                scale: 2,
                                child: Image.asset(
                                  'assets/branding/trans.png',
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'NUVO',
                          style: AppTextStyles.titleLarge.copyWith(
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'Choose your Arena',
                      style: AppTextStyles.displaySmall.copyWith(
                        color: const Color(0xFF07152C),
                        height: 1.04,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pick how you want to view the race.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: const Color(0xFF657286),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final style in NuvoPreviewStyle.values) ...[
                      _StyleChoice(
                        style: style,
                        onTap: () => onSelected(style),
                      ),
                      if (style != NuvoPreviewStyle.values.last)
                        const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.lock_shield,
                          size: 16,
                          color: Color(0xFF738095),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This changes presentation only. Your progress '
                            'and crew stay exactly the same.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: const Color(0xFF738095),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({required this.style, required this.onTap});

  final NuvoPreviewStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.forStyle(style);
    return Semantics(
      button: true,
      label: 'Choose ${style.name}',
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: visual.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF07152C).withValues(alpha: 0.07),
                blurRadius: 22,
                spreadRadius: -12,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _MiniPreview(visual: visual),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.name,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: const Color(0xFF07152C),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      style.description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color(0xFF657286),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: visual.action,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.arrow_right,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.visual});

  final NuvoVisualTheme visual;

  @override
  Widget build(BuildContext context) {
    final style = visual.style;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 82,
        height: 112,
        color: visual.page,
        child: switch (style) {
          NuvoPreviewStyle.startingLine => const _StartingLineMini(),
          NuvoPreviewStyle.trackside => const _TracksideMini(),
          NuvoPreviewStyle.crewMomentum => const _CrewMomentumMini(),
        },
      ),
    );
  }
}

class _StartingLineMini extends StatelessWidget {
  const _StartingLineMini();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(26, const Color(0xFF07152C)),
          const SizedBox(height: 10),
          _bar(39, const Color(0xFF07152C)),
          const SizedBox(height: 4),
          Row(
            children: [
              _bar(18, const Color(0xFF176BEE), height: 8),
              const SizedBox(width: 3),
              _bar(22, const Color(0xFF07152C), height: 8),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 6; i++) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i < 4
                        ? const Color(0xFF176BEE)
                        : const Color(0xFFDDE3EB),
                    shape: BoxShape.circle,
                  ),
                ),
                if (i < 5)
                  Expanded(
                    child: Container(
                      height: 1,
                      color: i < 3
                          ? const Color(0xFF176BEE)
                          : const Color(0xFFDDE3EB),
                    ),
                  ),
              ],
            ],
          ),
          const Spacer(),
          Container(height: 11, color: const Color(0xFF176BEE)),
          const SizedBox(height: 7),
          _bar(32, const Color(0xFF69788C), height: 3),
        ],
      ),
    );
  }
}

class _TracksideMini extends StatelessWidget {
  const _TracksideMini();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF07152C),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _bar(24, Colors.white70),
                ),
                const SizedBox(height: 5),
                _bar(37, Colors.white),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _bar(17, const Color(0xFF327BFF), height: 8),
                    const SizedBox(width: 3),
                    _bar(20, Colors.white, height: 8),
                  ],
                ),
                const Spacer(),
                Container(
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF327BFF),
                      width: 3,
                    ),
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(60, 18),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(height: 8, color: const Color(0xFF327BFF)),
              ],
            ),
          ),
        ),
        Container(
          height: 26,
          padding: const EdgeInsets.all(7),
          color: Colors.white,
          child: Column(
            children: [
              _bar(28, const Color(0xFF69788C), height: 3),
              const SizedBox(height: 5),
              _bar(52, const Color(0xFFDDE3EB), height: 3),
            ],
          ),
        ),
        Container(height: 9, color: const Color(0xFF07152C)),
      ],
    );
  }
}

class _CrewMomentumMini extends StatelessWidget {
  const _CrewMomentumMini();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bar(28, const Color(0xFF07152C)),
              const Spacer(),
              _bar(12, const Color(0xFF69788C), height: 3),
            ],
          ),
          const SizedBox(height: 8),
          _bar(42, const Color(0xFF07152C)),
          const SizedBox(height: 5),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF176BEE),
                      width: 3,
                    ),
                  ),
                ),
                for (final offset in const [
                  Offset(0, -23),
                  Offset(-23, 4),
                  Offset(23, 4),
                  Offset(0, 23),
                ])
                  Transform.translate(
                    offset: offset,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFBF765F),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Container(height: 10, color: const Color(0xFF176BEE)),
          const SizedBox(height: 6),
          _bar(48, const Color(0xFFE1DDD5), height: 3),
        ],
      ),
    );
  }
}

Widget _bar(double width, Color color, {double height = 4}) => Container(
  width: width,
  height: height,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(2),
  ),
);
