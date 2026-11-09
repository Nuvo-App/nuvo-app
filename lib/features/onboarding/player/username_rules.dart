/// Username rules for the S7 player card. Mirrors the server rule the v1
/// profile step already enforces: 3-20 letters, numbers or underscore.
abstract final class ObUsernameRules {
  static const int minLength = 3;
  static const int maxLength = 20;

  /// Canonical form sent to the server: trimmed, lower-case, no leading @.
  static String normalize(String raw) {
    var v = raw.trim().toLowerCase();
    while (v.startsWith('@')) {
      v = v.substring(1);
    }
    return v;
  }

  /// The real reason [normalized] can't be used, or null when the format is
  /// fine. Short input returns null (still typing, nothing to complain about).
  static String? formatError(String normalized) {
    if (normalized.length < minLength) return null;
    if (RegExp(r'\s').hasMatch(normalized)) {
      return "Usernames can't contain spaces.";
    }
    if (normalized.length > maxLength) {
      return 'Usernames can be at most $maxLength characters.';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(normalized)) {
      return 'Use only letters, numbers, or underscore.';
    }
    return null;
  }

  /// True when the format alone is acceptable (availability is separate).
  static bool isValidFormat(String normalized) =>
      normalized.length >= minLength && formatError(normalized) == null;

  /// Two one-tap alternatives for a taken [base]. Always valid format and
  /// within the length limit.
  static List<String> alternatives(String base) {
    final clean = base.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (clean.length < minLength) return const [];
    String fit(String stem, String suffix) {
      final room = maxLength - suffix.length;
      final s = stem.length > room ? stem.substring(0, room) : stem;
      return '$s$suffix';
    }

    final out = <String>[fit(clean, '12'), fit(clean, '_1')];
    return out.where((a) => a != base).toList();
  }
}
