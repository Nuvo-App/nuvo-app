import '../../features/auth/data/auth_api.dart' show ApiException;

/// Shows the server's message for client errors (4xx, which are written to be
/// read) and a neutral [fallback] for server/network failures (5xx and up).
String friendlyApiError(
  ApiException e, {
  String fallback = 'Something went wrong. Try again.',
}) {
  if (e.statusCode >= 500 || e.message.trim().isEmpty) return fallback;
  return e.message;
}
