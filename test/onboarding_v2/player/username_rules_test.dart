import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/player/username_rules.dart';

void main() {
  group('ObUsernameRules', () {
    test('normalize trims, lower-cases, strips @', () {
      expect(ObUsernameRules.normalize('  @Akshay_9 '), 'akshay_9');
    });

    test('short input has no error but is not valid', () {
      expect(ObUsernameRules.formatError('ab'), isNull);
      expect(ObUsernameRules.isValidFormat('ab'), isFalse);
    });

    test('rejects spaces, symbols and over-length', () {
      expect(ObUsernameRules.formatError('a b c'), isNotNull);
      expect(ObUsernameRules.formatError('ab-cd'), isNotNull);
      expect(ObUsernameRules.formatError('a' * 21), isNotNull);
      expect(ObUsernameRules.isValidFormat('a' * 20), isTrue);
      expect(ObUsernameRules.isValidFormat('ok_name1'), isTrue);
    });

    test('alternatives are valid format and fit the limit', () {
      final alts = ObUsernameRules.alternatives('squatking');
      expect(alts, ['squatking12', 'squatking_1']);
      final long = ObUsernameRules.alternatives('a' * 20);
      for (final a in long) {
        expect(ObUsernameRules.isValidFormat(a), isTrue, reason: a);
      }
      expect(ObUsernameRules.alternatives('ab'), isEmpty);
    });
  });
}
