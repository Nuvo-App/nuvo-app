import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set when a fresh account finishes onboarding: the app shows ONE small
/// welcome toast ("+100 XP, you're Level 2") and clears it. A reward, never
/// a gate.
final welcomeRewardProvider = StateProvider<bool>((ref) => false);
