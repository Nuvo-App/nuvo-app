// Every public profile offers the same "Add friend" action — an add is
// always a request until the other person accepts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/crew/presentation/public_profile_screen.dart';

class _Repo implements CrewRepository {
  @override
  Future<PublicProfileCard> getUser(String userId) async => PublicProfileCard(
        id: userId,
        displayName: 'Sam Rivera',
        initials: 'SR',
        connectionStatus: CrewConnectionStatus.none,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('public profile of any user shows Add friend', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [crewRepositoryProvider.overrideWithValue(_Repo())],
      child: const MaterialApp(home: PublicProfileScreen(userId: 'u2')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Add friend'), findsOneWidget);
    expect(find.text('Send friend request'), findsNothing);
  });
}
