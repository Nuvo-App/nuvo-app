import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/demo/presentation_demo.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/nuvo_theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    debugPrint('NUVO DEBUG BUILD MARKER: stage6-custom-verifier-live');
    debugPrint('NUVO DEBUG ENTRYPOINT: lib/main.dart');
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Dark status bar icons globally — icy-white backgrounds need this.
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
  // Resolve the local mode before controllers choose real data or fixtures.
  await ensurePresentationModeLoaded();
  // Resolve the persisted light/dark choice before the first frame.
  await ensureNuvoThemeModeLoaded();
  runApp(const ProviderScope(child: NuvoApp()));
}
