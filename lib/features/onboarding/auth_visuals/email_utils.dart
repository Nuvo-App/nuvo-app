import 'dart:math' as math;

/// Pure helpers for the S5 email screen (format check, domain chips, typo
/// hint). No Flutter imports so they unit-test directly.
abstract final class ObEmail {
  static final RegExp _format = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// The two always-offered domains.
  static const List<String> commonDomains = ['gmail.com', 'icloud.com'];

  /// Domains we compare typos against.
  static const List<String> _knownDomains = [
    'gmail.com',
    'icloud.com',
    'outlook.com',
    'yahoo.com',
    'hotmail.com',
  ];

  /// Real domains that sit one edit from a known one — never "corrected".
  static const Set<String> _realNeighbours = {
    'mail.com',
    'aol.com',
    'me.com',
    'msn.com',
    'live.com',
    'proton.me',
    'pm.me',
    'yahoo.co.uk',
    'googlemail.com',
    'hotmail.co.uk',
    'outlook.co.uk',
  };

  static String normalize(String raw) => raw.trim().toLowerCase();

  static bool isValid(String raw) => _format.hasMatch(normalize(raw));

  static String _local(String text) {
    final at = text.indexOf('@');
    return at < 0 ? text : text.substring(0, at);
  }

  static String _domain(String text) {
    final at = text.indexOf('@');
    return at < 0 ? '' : text.substring(at + 1);
  }

  /// Chips for the current text: gmail.com / icloud.com (filtered by what's
  /// typed after the "@") plus a school ".edu" completion of a bare domain
  /// stem. Empty until there is a local part to attach a domain to.
  static List<String> domainChips(String raw) {
    final text = raw.trim().toLowerCase();
    if (_local(text).isEmpty) return const [];
    final domain = _domain(text);
    final chips = <String>[
      for (final d in commonDomains)
        if (d != domain && d.startsWith(domain)) d,
    ];
    final stillTypingCommon = commonDomains.any((d) => d.startsWith(domain));
    if (domain.length >= 3 && !domain.contains('.') && !stillTypingCommon) {
      chips.add('$domain.edu');
    }
    return chips;
  }

  /// Replaces whatever follows the "@" (or appends one) with [domain].
  static String withDomain(String raw, String domain) =>
      '${_local(raw.trim())}@$domain';

  /// The domain the user probably meant, or null.
  static String? typoSuggestion(String raw) {
    final text = raw.trim().toLowerCase();
    final domain = _domain(text);
    if (_local(text).isEmpty || domain.length < 7 || !domain.contains('.')) {
      return null;
    }
    if (_knownDomains.contains(domain) || _realNeighbours.contains(domain)) {
      return null;
    }
    if (domain.endsWith('.edu')) return null;
    String? best;
    var bestDistance = 3;
    for (final known in _knownDomains) {
      // Still typing a known domain ("gmail.c") is not a typo.
      if (known.startsWith(domain)) return null;
      final d = _distance(domain, known);
      if (d < bestDistance) {
        bestDistance = d;
        best = known;
      }
    }
    return best;
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        cur[j] = math.min(
          math.min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
