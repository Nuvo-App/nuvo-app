import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_base.dart';
import '../../auth/data/auth_api.dart';

/// Verified proofs per local day (`GET /profile/activity`), keyed `YYYY-MM-DD`.
class ProfileActivityApi {
  ProfileActivityApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, int>> fetch(
    String token, {
    int days = 140,
    int? tzMinutes,
  }) async {
    final tz = tzMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
    final res = await _client
        .get(
          Uri.parse('$kNuvoApiBase/profile/activity?days=$days&tz=$tz'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Could not load activity');
    }
    final body = jsonDecode(res.body);
    final out = <String, int>{};
    if (body is Map && body['days'] is List) {
      for (final d in body['days'] as List) {
        if (d is Map && d['date'] is String && d['proofs'] is num) {
          out[d['date'] as String] = (d['proofs'] as num).toInt();
        }
      }
    }
    return out;
  }
}
