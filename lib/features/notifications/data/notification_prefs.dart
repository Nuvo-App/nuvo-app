import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/data/secure_token_store.dart';
import '../../../core/network/api_base.dart';


class NotificationPref {
  const NotificationPref({
    required this.category,
    required this.inApp,
    required this.push,
  });

  final String category;
  final bool inApp;
  final bool push;

  factory NotificationPref.fromJson(Map<String, dynamic> j) => NotificationPref(
        category: j['category'] as String,
        inApp: j['inApp'] as bool? ?? true,
        push: j['push'] as bool? ?? true,
      );

  /// Human label + which group a category belongs to.
  ({String label, String group}) get display => switch (category) {
        'race_invite' => (label: 'Race invites', group: 'Races'),
        'race_joined' => (label: 'New racer joins', group: 'Races'),
        'race_starting' => (label: 'Race starting', group: 'Races'),
        'race_completed' => (label: 'Race finished', group: 'Races'),
        'passed_on_leaderboard' => (label: 'Passed on leaderboard', group: 'Races'),
        'proof_accepted' => (label: 'Proof accepted', group: 'Proof'),
        'proof_rejected' => (label: 'Proof needs another try', group: 'Proof'),
        'proof_disputed' => (label: 'Proof disputes', group: 'Proof'),
        'crew_request' => (label: 'Crew requests', group: 'Crew'),
        'crew_request_accepted' => (label: 'Request accepted', group: 'Crew'),
        'crew_connected' => (label: 'New crew member', group: 'Crew'),
        'reaction' => (label: 'Reactions', group: 'Crew'),
        _ => (label: category, group: 'Other'),
      };
}

class NotificationPrefsApi {
  NotificationPrefsApi({http.Client? client, SecureTokenStore? store})
      : _client = client ?? http.Client(),
        _store = store ?? SecureTokenStore();

  final http.Client _client;
  final SecureTokenStore _store;

  Future<String> _token() async {
    final t = await _store.getAccessToken();
    if (t == null) throw const ApiException(401, 'Not authenticated');
    return t;
  }

  Future<List<NotificationPref>> list() async {
    final res = await _client
        .get(
          Uri.parse('$kNuvoApiBase/notifications/preferences'),
          headers: {'Authorization': 'Bearer ${await _token()}'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Could not load preferences');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['preferences'] as List<dynamic>)
        .map((e) => NotificationPref.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> update(String category, {bool? inApp, bool? push}) async {
    try {
      await _client
          .patch(
            Uri.parse('$kNuvoApiBase/notifications/preferences'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _token()}',
            },
            body: jsonEncode({
              'category': category,
              'inApp': ?inApp,
              'push': ?push,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException(408, 'Timed out saving your preference.');
    } on SocketException {
      throw const ApiException(0, "Can't reach Nuvo.");
    }
  }
}
