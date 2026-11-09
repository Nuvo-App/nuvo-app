// R4 (docs/statements/demo-account.md): the fake-data pill is reachable for
// testing@getnuvo.net only.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

void main() {
  test('R4: fake-data pill shows for testing@getnuvo.net only', () {
    expect(showFakeDataPill('testing@getnuvo.net'), isTrue);
    expect(showFakeDataPill(' Testing@GetNuvo.net '), isTrue);
    expect(showFakeDataPill('someone@getnuvo.net'), isFalse);
    expect(showFakeDataPill('testing@gmail.com'), isFalse);
    expect(showFakeDataPill(''), isFalse);
    expect(showFakeDataPill(null), isFalse);
  });
}
