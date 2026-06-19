import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Dark status bar icons globally — icy-white backgrounds need this.
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);
  runApp(const ProviderScope(child: NuvoApp()));
}
