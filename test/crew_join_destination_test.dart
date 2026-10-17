import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

void main() {
  test('a crew QR / link resolves to the join confirm screen', () {
    final d = NuvoDestination.tryParse(
      Uri.parse('https://getnuvo.net/c/abc123'),
    );
    expect(d, const CrewJoinDestination('ABC123'));
    expect(d!.location, '/crews/join/ABC123');
  });

  test('other links are unaffected', () {
    expect(
      NuvoDestination.tryParse(Uri.parse('https://getnuvo.net/invite/tok')),
      const InviteDestination('tok'),
    );
    expect(NuvoDestination.tryParse(Uri.parse('https://example.com/x')), isNull);
  });
}
