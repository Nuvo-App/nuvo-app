import 'package:web/web.dart';

const _key = 'nuvo_motion_catalog_lkg';

Future<String?> readMotionCatalogCache() async => window.localStorage.getItem(_key);

Future<void> writeMotionCatalogCache(String value) async => window.localStorage.setItem(_key, value);
