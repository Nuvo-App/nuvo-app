import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/social/data/invite_models.dart';

void main() {
  test('accept: 410 body status closed maps to InviteStatus.closed', () {
    final r = InviteAcceptResult.fromJson({'ok': false, 'status': 'closed'});
    expect(r.ok, isFalse);
    expect(r.status, InviteStatus.closed);
  });

  test('accept: error text about an ended race maps to closed', () {
    final r = InviteAcceptResult.fromJson({'error': 'This race has ended'});
    expect(r.status, InviteStatus.closed);
  });

  test('accept: unrelated error text stays unknown', () {
    final r = InviteAcceptResult.fromJson({'error': 'Something odd'});
    expect(r.status, InviteStatus.unknown);
  });

  test('preview: closed status is parsed and unavailable', () {
    final p = InvitePreview.fromJson({'status': 'closed', 'requiresAuth': false});
    expect(p.status, InviteStatus.closed);
    expect(p.isAvailable, isFalse);
  });

  test('ok accept still wins over any status text', () {
    final r = InviteAcceptResult.fromJson({'ok': true, 'status': 'closed'});
    expect(r.ok, isTrue);
  });
}
