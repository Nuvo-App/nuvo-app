import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class NuvoApp extends ConsumerWidget {
  const NuvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = MaterialApp.router(
      title: 'Nuvo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      builder: kIsWeb ? _webPreviewBuilder : null,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay,
      child: app,
    );
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
