import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/nuvo_responsive.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/social/application/deep_link_controller.dart';
import 'router.dart';

class NuvoApp extends ConsumerStatefulWidget {
  const NuvoApp({super.key});

  @override
  ConsumerState<NuvoApp> createState() => _NuvoAppState();
}

class _NuvoAppState extends ConsumerState<NuvoApp> {
  bool _deepLinksStarted = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Start link intake once the router exists (handles the cold-start link).
    if (!_deepLinksStarted) {
      _deepLinksStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(deepLinkControllerProvider).start(router);
      });
    }

    // When the user becomes authenticated, drain any destination that was
    // stashed while they were logged out (link → sign-in → original target).
    ref.listen<AuthState>(authControllerProvider, (prev, next) async {
      final becameAuthed = prev?.status != AuthStatus.authenticated &&
          next.status == AuthStatus.authenticated;
      if (!becameAuthed || !(next.user?.onboardingComplete ?? false)) return;
      final location = await ref.read(pendingDestinationStoreProvider).consume();
      if (location != null && location.isNotEmpty) router.go(location);
    });

    final app = MaterialApp.router(
      title: 'Nuvo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      builder: _appBuilder,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay,
      child: app,
    );
  }
}

Widget _appBuilder(BuildContext context, Widget? child) {
  final content = NuvoTextScaleScope(
    child: _KeyboardDismissScope(
      child: child ?? const SizedBox.shrink(),
    ),
  );
  if (kIsWeb) return _webPreviewBuilder(context, content);
  return content;
}

class _KeyboardDismissScope extends StatelessWidget {
  const _KeyboardDismissScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (notification) {
          if (notification.dragDetails != null) _dismissKeyboard();
          return false;
        },
        child: child,
      ),
    );
  }

  void _dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    focus.unfocus();
  }
}

// On large desktop browser viewports center the app in a 430 px phone column.
// On real mobile-sized viewports (≤ 600 px wide) the app fills normally.
Widget _webPreviewBuilder(BuildContext context, Widget? child) {
  final width = MediaQuery.sizeOf(context).width;
  final content = child ?? const SizedBox.shrink();
  if (width <= 600) return content;
  return Container(
    color: NuvoColors.page,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ClipRect(child: content),
      ),
    ),
  );
}
