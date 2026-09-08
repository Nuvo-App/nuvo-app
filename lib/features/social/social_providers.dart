import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/auth_controller.dart';
import 'data/invite_api.dart';
import 'data/invite_repository.dart';

final _inviteApiProvider = Provider<InviteApi>((_) => InviteApi());

final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(
    ref.watch(_inviteApiProvider),
    ref.watch(secureTokenStoreProvider),
    ref.watch(authApiProvider),
  ),
);
