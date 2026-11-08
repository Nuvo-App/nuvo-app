// Web analytics persistence — window.localStorage, matching the
// secure_token_store web adapter (_ls_web.dart).
import 'package:web/web.dart';

const _key = 'nuvo_analytics';

Future<String?> readAnalyticsPrefs() async => window.localStorage.getItem(_key);

Future<void> writeAnalyticsPrefs(String json) async =>
    window.localStorage.setItem(_key, json);
