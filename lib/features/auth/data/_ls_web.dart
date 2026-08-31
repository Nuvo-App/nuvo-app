// Web localStorage adapter using package:web (modern, dart:html-free).
// Only compiled on web via conditional import in secure_token_store.dart.
import 'package:web/web.dart';

void setItem(String key, String value) =>
    window.localStorage.setItem(key, value);
String? getItem(String key) => window.localStorage.getItem(key);
void removeItem(String key) => window.localStorage.removeItem(key);
