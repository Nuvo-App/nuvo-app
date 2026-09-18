import 'motion_catalog_cache_io.dart'
    if (dart.library.html) 'motion_catalog_cache_web.dart' as platform;

class MotionCatalogCache {
  Future<String?> read() => platform.readMotionCatalogCache();

  Future<void> write(String value) => platform.writeMotionCatalogCache(value);
}
