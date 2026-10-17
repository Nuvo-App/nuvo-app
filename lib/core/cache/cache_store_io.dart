import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cache_store.dart';

CacheStore createPlatformCacheStore() => FileCacheStore();

/// Stores `root/accountId/domain.json`. [root] defaults to
/// the app support directory plus `cache` and is injectable for tests.
class FileCacheStore implements CacheStore {
  FileCacheStore({this.root});

  final Directory? root;

  Future<Directory> _rootDir() async {
    final injected = root;
    if (injected != null) return injected;
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/cache');
  }

  Future<File> _file(String accountId, String domain) async {
    final root = await _rootDir();
    return File('${root.path}/$accountId/$domain.json');
  }

  Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  @override
  Future<CacheEntry?> read(
    String accountId,
    String domain, {
    Duration? maxAge,
  }) async {
    if (!isValidCacheId(accountId) || !isValidCacheId(domain)) return null;
    File? file;
    try {
      file = await _file(accountId, domain);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        await _delete(file);
        return null;
      }
      if (decoded['schema'] != kCacheSchema) {
        await _delete(file);
        return null;
      }
      final savedRaw = decoded['savedAt'];
      final savedAt = savedRaw is String ? DateTime.tryParse(savedRaw) : null;
      if (savedAt == null) {
        await _delete(file);
        return null;
      }
      final etag = decoded['etag'];
      final entry = CacheEntry(
        schema: kCacheSchema,
        savedAt: savedAt.toUtc(),
        etag: etag is String ? etag : null,
        data: decoded['data'],
      );
      if (maxAge != null &&
          DateTime.now().toUtc().difference(entry.savedAt) > maxAge) {
        return null;
      }
      return entry;
    } catch (_) {
      if (file != null) await _delete(file);
      return null;
    }
  }

  @override
  Future<void> write(
    String accountId,
    String domain,
    Object? json, {
    String? etag,
  }) async {
    if (!isValidCacheId(accountId) || !isValidCacheId(domain)) return;
    try {
      final file = await _file(accountId, domain);
      await file.parent.create(recursive: true);
      final body = jsonEncode({
        'schema': kCacheSchema,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'etag': etag,
        'data': json,
      });
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(body, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // A cache write must never break the caller.
    }
  }

  @override
  Future<void> clearAccount(String accountId) async {
    if (!isValidCacheId(accountId)) return;
    try {
      final root = await _rootDir();
      final dir = Directory('${root.path}/$accountId');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    try {
      final root = await _rootDir();
      if (root.existsSync()) await root.delete(recursive: true);
    } catch (_) {}
  }
}
