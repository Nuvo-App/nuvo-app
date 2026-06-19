import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class NuvoApp extends ConsumerWidget {
  const NuvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay,
      child: MaterialApp.router(
        title: 'Nuvo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
