import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';

/// One entry point for "tap a face, open that person" across the v13 shell.
///
/// The signed-in user goes to their own Profile tab (`/profile`); everyone
/// else pushes their public profile (`/u/:id`).
void openPerson(BuildContext context, WidgetRef ref, String userId) {
  final myId = ref.read(authControllerProvider).user?.id;
  if (myId != null && myId == userId) {
    context.go('/profile');
  } else {
    context.push('/u/${Uri.encodeComponent(userId)}');
  }
}
