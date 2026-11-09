import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/offline/outbox.dart';
import 'package:nuvo/features/auth/data/auth_api.dart' show ApiException;

void main() {
  late DateTime now;
  Outbox make() => Outbox.memory(now: () => now);

  setUp(() => now = DateTime(2026, 11, 9, 12));

  test('enqueue is idempotent by id', () async {
    final o = make();
    await o.enqueue(OutboxEntry(id: 'join:r1', kind: 'race.join', payload: {}));
    await o.enqueue(OutboxEntry(id: 'join:r1', kind: 'race.join', payload: {}));
    expect(o.pendingCount, 1);
  });

  test('upsert keeps only the newest entry for an id', () async {
    final o = make();
    await o.upsert(OutboxEntry(id: 'react:x', kind: 'k', payload: {'e': 'a'}));
    await o.upsert(OutboxEntry(id: 'react:x', kind: 'k', payload: {'e': 'b'}));
    expect(o.pendingCount, 1);
    expect(o.entries.single.payload['e'], 'b');
  });

  test('flush sends due entries and removes them', () async {
    final o = make();
    final sent = <String>[];
    o.registerHandler('race.join', (p) async => sent.add(p['raceId'] as String));
    await o.enqueue(
      OutboxEntry(id: 'join:r1', kind: 'race.join', payload: {'raceId': 'r1'}),
    );
    expect(await o.flush(), 1);
    expect(sent, ['r1']);
    expect(o.pendingCount, 0);
    expect(o.lastReachable, isTrue);
  });

  test('network failure keeps the entry and backs off', () async {
    final o = make();
    o.registerHandler('k', (_) async => throw const ApiException(0, 'offline'));
    await o.enqueue(OutboxEntry(id: 'a', kind: 'k', payload: {}));
    expect(await o.flush(), 0);
    expect(o.pendingCount, 1);
    expect(o.entries.single.attempts, 1);
    expect(o.lastReachable, isFalse);
    // Not due yet → skipped; force retries now.
    expect(await o.flush(), 0);
    expect(o.entries.single.attempts, 1);
    now = now.add(o.backoffFor(1));
    await o.flush();
    expect(o.entries.single.attempts, 2);
  });

  test('a real server answer drops the entry (no infinite retry)', () async {
    final o = make();
    o.registerHandler('k', (_) async => throw const ApiException(409, 'no'));
    await o.enqueue(OutboxEntry(id: 'a', kind: 'k', payload: {}));
    await o.flush();
    expect(o.pendingCount, 0);
  });

  test('entries round-trip through JSON (persistence format)', () {
    final e = OutboxEntry(
      id: 'proof:r1:1',
      kind: 'race.proof.manual',
      payload: {'raceId': 'r1', 'value': 12},
      attempts: 3,
    );
    final back = OutboxEntry.fromJson(e.toJson())!;
    expect(back.id, e.id);
    expect(back.kind, e.kind);
    expect(back.payload, e.payload);
    expect(back.attempts, 3);
  });

  test('isNetworkFailure covers unreachable and (optionally) timeouts', () {
    expect(isNetworkFailure(const ApiException(0, '')), isTrue);
    expect(isNetworkFailure(const ApiException(408, '')), isTrue);
    expect(
      isNetworkFailure(const ApiException(408, ''), includeTimeout: false),
      isFalse,
    );
    expect(isNetworkFailure(const ApiException(500, '')), isFalse);
  });
}
