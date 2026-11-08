// Native analytics persistence — a JSON file in the app documents directory,
// the same pattern as FirstUseStore / NuvoThemeModeStore.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/nuvo_analytics.json');
}

Future<String?> readAnalyticsPrefs() async {
  try {
    final file = await _file();
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeAnalyticsPrefs(String json) async {
  try {
    await (await _file()).writeAsString(json);
  } catch (_) {
    // Best-effort persistence — a failed write just reverts to defaults.
  }
}
