import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/nuvo_preview_controller.dart';
import '../core/design/nuvo_preview_style.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../features/shell/presentation/main_shell.dart';
import 'router.dart';

class NuvoApp extends ConsumerWidget {
  const NuvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(activeNuvoPreviewStyleProvider);
    final visual = NuvoVisualTheme.forStyle(style);
    const visualQa = bool.fromEnvironment('NUVO_VISUAL_QA');
    final app = MaterialApp.router(
      title: 'Nuvo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(style: style),
      routerConfig: ref.watch(routerProvider),
      builder: _appBuilder,
    );
    final qaApp = MaterialApp(
      title: 'Nuvo visual QA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(style: style),
      home: const ConferenceVisualQaScreen(),
      builder: _appBuilder,
    );

    final overlay = AppTheme.overlay.copyWith(
      statusBarIconBrightness: visual.darkHero
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: visual.darkHero ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: visual.navigation,
      systemNavigationBarIconBrightness: visual.darkHero
          ? Brightness.light
          : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: visualQa ? qaApp : app,
    );
  }
}

Widget _appBuilder(BuildContext context, Widget? child) {
  final content = _KeyboardDismissScope(
    child: child ?? const SizedBox.shrink(),
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
