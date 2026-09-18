import 'verifier_release_cache_io.dart'
    if (dart.library.html) 'verifier_release_cache_web.dart'
    as platform;

class VerifierReleaseCache {
  Future<Map<String, dynamic>> read() => platform.readVerifierReleases();

  Future<void> write(Map<String, dynamic> value) =>
      platform.writeVerifierReleases(value);
}
