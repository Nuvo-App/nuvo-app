// ignore_for_file: use_null_aware_elements
// Crash-safe readers for server JSON.
//
// The Worker may return null, omit a field, or change a number between int,
// double and String. A hard cast (`as int`, `as String`, `as List`) on any of
// those throws "type 'Null' is not a subtype..." and takes a whole screen or
// action down. Every fromJson reads through these instead: nothing here ever
// throws, and an unreadable value comes back as null (or an empty collection).

/// Reads an int from an int, a whole/fractional number, or a numeric String.
int? jInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt();
  }
  return null;
}

/// Reads a double from a number or numeric String.
double? jDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// Reads a String; numbers and bools are stringified, everything else is null.
String? jStr(Object? v) {
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

/// Reads a bool from a bool, 0/1, or 'true'/'false'.
bool? jBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}

/// Reads a JSON object as `Map<String, dynamic>`, or null.
Map<String, dynamic>? jMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    try {
      return Map<String, dynamic>.from(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Reads a JSON list; anything else (null, object, String) is an empty list.
List<dynamic> jList(Object? v) => v is List ? v : const [];

/// Reads a JSON list of objects, skipping entries that are not objects.
List<Map<String, dynamic>> jMapList(Object? v) {
  if (v is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    final m = jMap(e);
    if (m != null) out.add(m);
  }
  return out;
}
