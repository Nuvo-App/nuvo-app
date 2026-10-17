import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cache_store_io.dart'
    if (dart.library.html) 'cache_store_stub.dart'
    as platform;

/// Bump when the envelope shape changes. Entries with another schema are
/// discarded on read.
const int kCacheSchema = 1;

final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// True when [value] is safe to use as a path segment (no '.', '/', etc.).
bool isValidCacheId(String value) => _safeId.hasMatch(value);

class CacheEntry {
  const CacheEntry({
    required this.schema,
    required this.savedAt,
    this.etag,
    this.data,
  });

  final int schema;
  final DateTime savedAt;
  final String? etag;
  final Object? data;
}

/// Per-account cache of JSON-encodable data. Never throws to callers and
/// must never hold tokens.
abstract class CacheStore {
  factory CacheStore.memory() = MemoryCacheStore;

  Future<CacheEntry?> read(String accountId, String domain, {Duration? maxAge});

  Future<void> write(
    String accountId,
    String domain,
    Object? json, {
    String? etag,
  });

  Future<void> clearAccount(String accountId);

  Future<void> clearAll();
}

class MemoryCacheStore implements CacheStore {
  MemoryCacheStore();

  final Map<String, Map<String, CacheEntry>> _accounts = {};

  @override
  Future<CacheEntry?> read(
    String accountId,
    String domain, {
    Duration? maxAge,
  }) async {
    if (!isValidCacheId(accountId) || !isValidCacheId(domain)) return null;
    final entry = _accounts[accountId]?[domain];
    if (entry == null) return null;
    if (entry.schema != kCacheSchema) {
      _accounts[accountId]?.remove(domain);
      return null;
    }
    if (maxAge != null &&
        DateTime.now().toUtc().difference(entry.savedAt) > maxAge) {
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(
    String accountId,
    String domain,
    Object? json, {
    String? etag,
  }) async {
    if (!isValidCacheId(accountId) || !isValidCacheId(domain)) return;
    (_accounts[accountId] ??= {})[domain] = CacheEntry(
      schema: kCacheSchema,
      savedAt: DateTime.now().toUtc(),
      etag: etag,
      data: json,
    );
  }

  @override
  Future<void> clearAccount(String accountId) async {
    if (!isValidCacheId(accountId)) return;
    _accounts.remove(accountId);
  }

  @override
  Future<void> clearAll() async => _accounts.clear();
}

/// File-backed in the app; in-memory on web.
final cacheStoreProvider = Provider<CacheStore>(
  (ref) => platform.createPlatformCacheStore(),
);
