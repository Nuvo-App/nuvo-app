import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/analytics/analytics_service.dart';
import 'core/config/nuvo_flags.dart';
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
  // Load the persisted analytics opt-out + install id (consent resolved
  // before anything starts), then PostHog when a POSTHOG_API_KEY was
  // compiled in — a missing key keeps it a no-op.
  await ensureAnalyticsLoaded();
  // Crash reporting rides the same guard as PushService: Firebase throws
  // without GoogleService-Info.plist / google-services.json, and the app
  // just keeps running with crash capture off.
  try {
    await Firebase.initializeApp();
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {}
  // Server switches load in the background; defaults are the safe ones.
  unawaited(NuvoFlags.load());
  runApp(const ProviderScope(child: NuvoApp()));
}
