// Stub for non-web platforms. Imported via conditional import in
// secure_token_store.dart; these functions are never called on native —
// flutter_secure_storage handles that path instead.
void setItem(String key, String value) {}
String? getItem(String key) => null;
void removeItem(String key) {}
