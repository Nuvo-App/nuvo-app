import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';

class _Store extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'test-token';
}

class _Api extends ProgressionApi {
  _Api() : super(client: null);

  int calls = 0;
  final pending = <Completer<NuvoProgression>>[];
  bool fail = false;

  @override
  Future<ProgressionFetch> getProgressionConditional(
    String token, {
    String? etag,
  }) async =>
      ProgressionFetch(data: await getProgression(token));

  @override
  Future<NuvoProgression> getProgression(String token) {
    calls++;
    if (fail) return Future.error(Exception('boom'));
    final c = Completer<NuvoProgression>();
    pending.add(c);
    return c.future;
  }
}

NuvoProgression _p(int level) => NuvoProgression.fromJson({'level': level});

void main() {
  test('concurrent loads share one request (single-flight)', () async {
    final api = _Api();
    final c = ProgressionController(api, _Store());
    final a = c.load();
    final b = c.load();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, 1);
    api.pending.single.complete(_p(3));
    await Future.wait([a, b]);
    expect(c.state.valueOrNull?.level, 3);
  });

  test('revalidate inside the stale window makes no call', () async {
    final api = _Api();
    final c = ProgressionController(api, _Store());
    final first = c.load();
    await Future<void>.delayed(Duration.zero);
    api.pending.single.complete(_p(2));
    await first;
    c.revalidate();
    await c.load(force: false);
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, 1);
  });

  test('clear during an in-flight load discards the result', () async {
    final api = _Api();
    final c = ProgressionController(api, _Store());
    final stale = c.load();
    await Future<void>.delayed(Duration.zero);
    c.clear();
    // Next session starts a fresh request rather than awaiting the old one.
    final next = c.load();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, 2);
    api.pending[0].complete(_p(9));
    await stale;
    expect(c.state.hasValue, isFalse);
    api.pending[1].complete(_p(1));
    await next;
    expect(c.state.valueOrNull?.level, 1);
  });

  test('failed refresh keeps the last good value', () async {
    final api = _Api();
    final c = ProgressionController(api, _Store());
    final first = c.load();
    await Future<void>.delayed(Duration.zero);
    api.pending.single.complete(_p(4));
    await first;
    api.fail = true;
    await c.load();
    expect(api.calls, 2);
    expect(c.state.valueOrNull?.level, 4);
  });
}
