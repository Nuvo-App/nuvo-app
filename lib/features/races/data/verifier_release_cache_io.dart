import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _fileName = 'nuvo_verifier_releases.json';

Future<File> _file() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$_fileName');
}

Future<Map<String, dynamic>> readVerifierReleases() async {
  try {
    final file = await _file();
    if (!file.existsSync()) return {};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : {};
  } catch (_) {
    return {};
  }
}

Future<void> writeVerifierReleases(Map<String, dynamic> value) async {
  try {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    // A cache write must never block a valid release from being used.
  }
}
