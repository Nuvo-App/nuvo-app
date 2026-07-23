import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/nuvo_preview_controller.dart';
import '../../../core/design/nuvo_preview_style.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/preview_style_chooser.dart';
import '../../arena/presentation/arena_screen_fixed.dart';
import '../../compete/presentation/compete_screen_fixed.dart';
import '../../move/presentation/move_screen.dart';
import '../../pass/presentation/pass_screen.dart';
import '../../profile/presentation/profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

/// Compile-time-only visual QA surface. Production routing never references
/// this widget.
class ConferenceVisualQaScreen extends ConsumerWidget {
  const ConferenceVisualQaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedStyle = ref.watch(nuvoPreviewStyleProvider);
    if (selectedStyle == null) {
      return PreviewStyleChooser(
        onSelected: (style) =>
            ref.read(nuvoPreviewStyleProvider.notifier).select(style),
      );
    }

    final visual = NuvoVisualTheme.of(context);
    return Scaffold(
      backgroundColor: visual.page,
      body: const ArenaStylePreview(),
      bottomNavigationBar: NuvoBottomNav(currentIndex: 0, onTap: (_) {}),
    );
  }
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  // Maps nav index → shell route path.
  static const _paths = [
    '/arena', // 0 Arena
    '/compete', // 1 Races
    '/move', // 2 Verify
    '/pass', // 3 Crew
    '/profile', // 4 Profile
  ];

  static const _pages = [
    ArenaScreen(),
    CompeteScreen(),
    MoveScreen(),
    PassScreen(),
    ProfileScreen(),
  ];

  int _indexFor(String location) {
    if (location.startsWith('/compete')) return 1;
    if (location.startsWith('/move')) return 2;
    if (location.startsWith('/pass')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = GoRouterState.of(context).uri.path;
    final newIndex = _indexFor(location);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
    }
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final selectedStyle = ref.watch(nuvoPreviewStyleProvider);
    if (selectedStyle == null) {
      return PreviewStyleChooser(
        onSelected: (style) {
          ref.read(nuvoPreviewStyleProvider.notifier).select(style);
        },
      );
    }

    final visual = NuvoVisualTheme.of(context);
    return Scaffold(
      backgroundColor: visual.page,
      extendBody: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < _pages.length; index++)
            IgnorePointer(
              ignoring: index != _currentIndex,
              child: ExcludeSemantics(
                excluding: index != _currentIndex,
                child: TickerMode(
                  enabled: index == _currentIndex,
                  child: AnimatedSlide(
                    offset: index == _currentIndex
                        ? Offset.zero
                        : Offset(index < _currentIndex ? -0.025 : 0.025, 0),
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: index == _currentIndex ? 1 : 0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: RepaintBoundary(child: _pages[index]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NuvoBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
