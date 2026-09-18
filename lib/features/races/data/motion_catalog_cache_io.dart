import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _fileName = 'motion_catalog_lkg.json';

Future<File> _file() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$_fileName');
}

Future<String?> readMotionCatalogCache() async {
  try {
    final file = await _file();
    return file.existsSync() ? file.readAsString() : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeMotionCatalogCache(String value) async {
  try {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    // A cache write must never block catalog use or race creation.
  }
}
