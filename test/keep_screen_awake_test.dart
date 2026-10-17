import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/keep_screen_awake.dart';

void main() {
  late List<bool> calls;

  setUp(() {
    calls = [];
    KeepScreenAwake.holders = 0;
    KeepScreenAwake.setWakelock = (enable) async => calls.add(enable);
  });

  tearDown(() {
    KeepScreenAwake.holders = 0;
  });

  Widget host(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: child);

  testWidgets('holds the screen on while mounted and releases on dispose',
      (tester) async {
    await tester.pumpWidget(host(const KeepScreenAwake(child: Text('x'))));
    expect(calls, [true]);
    await tester.pumpWidget(host(const SizedBox()));
    expect(calls, [true, false]);
    expect(KeepScreenAwake.holders, 0);
  });

  testWidgets('overlapping holders keep the lock until the last one leaves',
      (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      KeepScreenAwake(child: Text('a')),
      KeepScreenAwake(child: Text('b')),
    ])));
    expect(calls, [true], reason: 'second holder must not re-enable');
    expect(KeepScreenAwake.holders, 2);

    await tester.pumpWidget(host(const Column(children: [
      KeepScreenAwake(child: Text('a')),
    ])));
    expect(calls, [true], reason: 'one holder left — still on');

    await tester.pumpWidget(host(const SizedBox()));
    expect(calls, [true, false]);
  });

  testWidgets('enabled:false releases without unmounting and can re-acquire',
      (tester) async {
    Widget build(bool on) =>
        host(KeepScreenAwake(enabled: on, child: const Text('x')));
    await tester.pumpWidget(build(true));
    await tester.pumpWidget(build(false));
    expect(calls, [true, false]);
    await tester.pumpWidget(build(true));
    expect(calls, [true, false, true]);
  });

  testWidgets('a failing platform call never breaks the screen',
      (tester) async {
    KeepScreenAwake.setWakelock = (_) async => throw StateError('no plugin');
    await tester.pumpWidget(host(const KeepScreenAwake(child: Text('ok'))));
    expect(find.text('ok'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(const SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a synchronously throwing platform call is also swallowed',
      (tester) async {
    KeepScreenAwake.setWakelock = (_) => throw StateError('sync');
    await tester.pumpWidget(host(const KeepScreenAwake(child: Text('ok'))));
    expect(find.text('ok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
