import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/cache/cache_store_io.dart';

void main() {
  late Directory root;
  late FileCacheStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nuvo_cache_test');
    store = FileCacheStore(root: Directory('${root.path}/cache'));
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('memory store round trip', () async {
    final s = CacheStore.memory();
    expect(await s.read('a1', 'races'), isNull);
    await s.write('a1', 'races', {'x': 1}, etag: 'e1');
    final e = await s.read('a1', 'races');
    expect(e!.data, {'x': 1});
    expect(e.etag, 'e1');
    expect(e.schema, kCacheSchema);
    expect(await s.read('a2', 'races'), isNull);
    await s.clearAccount('a1');
    expect(await s.read('a1', 'races'), isNull);
  });

  test('file store round trip', () async {
    await store.write('a1', 'races', {
      'list': [1, 2],
    }, etag: 'abc');
    final e = await store.read('a1', 'races');
    expect(e!.data, {
      'list': [1, 2],
    });
    expect(e.etag, 'abc');
    expect(e.savedAt.isUtc, isTrue);
    expect(
      File('${root.path}/cache/a1/races.json.tmp').existsSync(),
      isFalse,
    );
  });

  test('schema mismatch discards the file', () async {
    final file = File('${root.path}/cache/a1/races.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schema': kCacheSchema + 1,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'etag': null,
        'data': 1,
      }),
    );
    expect(await store.read('a1', 'races'), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('maxAge returns null without deleting', () async {
    final file = File('${root.path}/cache/a1/races.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schema': kCacheSchema,
        'savedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
        'etag': null,
        'data': 'old',
      }),
    );
    expect(
      await store.read('a1', 'races', maxAge: const Duration(hours: 1)),
      isNull,
    );
    expect(file.existsSync(), isTrue);
    expect(
      (await store.read('a1', 'races', maxAge: const Duration(hours: 3)))!.data,
      'old',
    );
    expect((await store.read('a1', 'races'))!.data, 'old');
  });

  test('corrupt file returns null and is deleted', () async {
    final file = File('${root.path}/cache/a1/races.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{not json');
    expect(await store.read('a1', 'races'), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('clearAccount only clears that account', () async {
    await store.write('a1', 'races', 1);
    await store.write('a2', 'races', 2);
    await store.clearAccount('a1');
    expect(await store.read('a1', 'races'), isNull);
    expect((await store.read('a2', 'races'))!.data, 2);
    await store.clearAll();
    expect(await store.read('a2', 'races'), isNull);
  });

  test('path traversal ids are rejected', () async {
    for (final bad in ['..', '../x', 'a/b', '', 'a.b', r'a\b']) {
      await store.write(bad, 'races', 1);
      await store.write('a1', bad, 1);
      expect(await store.read(bad, 'races'), isNull);
      expect(await store.read('a1', bad), isNull);
    }
    expect(File('${root.path}/races.json').existsSync(), isFalse);
    expect(File('${root.path}/cache/races.json').existsSync(), isFalse);
    final memory = CacheStore.memory();
    await memory.write('..', 'races', 1);
    expect(await memory.read('..', 'races'), isNull);
  });

  test('two accounts never see each other data', () async {
    await store.write('a1', 'races', 'one');
    await store.write('a2', 'races', 'two');
    expect((await store.read('a1', 'races'))!.data, 'one');
    expect((await store.read('a2', 'races'))!.data, 'two');
    expect(await store.read('a3', 'races'), isNull);
  });
}
