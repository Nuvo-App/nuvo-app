import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../features/auth/data/auth_models.dart';

/// Last signed-in user, saved on device so a cold open with no network still
/// shows the real person (name, @handle, photo) instead of "Nuvo member".
/// Written after every authenticated state, cleared on a real sign-out.
/// Local only — never sent anywhere.
class UserSnapshotStore {
  UserSnapshotStore({this.memoryOnly = false});

  /// In-memory for tests.
  UserSnapshotStore.memory() : this(memoryOnly: true);

  final bool memoryOnly;
  Map<String, dynamic>? _memory;

  static Map<String, dynamic> toJson(AuthUser u) => {
    'id': u.id,
    'email': u.email,
    'isDemo': u.isDemo,
    'fullName': u.fullName,
    'username': u.username,
    'onboardingComplete': u.onboardingComplete,
    'hasMemberPass': u.hasMemberPass,
    'termsAccepted': u.termsAccepted,
    'ageAttested': u.ageAttested,
    'motionTrainingConsent': u.motionTrainingConsent,
    'profilePhotoUrl': u.profilePhotoUrl,
  };

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_user_snapshot.json');
  }

  Future<void> write(AuthUser user) async {
    final json = toJson(user);
    if (memoryOnly) {
      _memory = json;
      return;
    }
    try {
      await (await _file()).writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  Future<AuthUser?> read() async {
    try {
      final Map<String, dynamic>? json;
      if (memoryOnly) {
        json = _memory;
      } else {
        final f = await _file();
        if (!await f.exists()) return null;
        final decoded = jsonDecode(await f.readAsString());
        json = decoded is Map<String, dynamic> ? decoded : null;
      }
      return json == null ? null : AuthUser.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _memory = null;
    if (memoryOnly) return;
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

final userSnapshotStore = UserSnapshotStore();
