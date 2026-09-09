import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/data/secure_token_store.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

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
        'race_joined' => (label: 'Someone joins your race', group: 'Races'),
        'race_starting' => (label: 'A race is about to start', group: 'Races'),
        'race_completed' => (label: 'A race finishes', group: 'Races'),
        'passed_on_leaderboard' => (label: 'Someone passes you', group: 'Races'),
        'proof_accepted' => (label: 'Your proof is accepted', group: 'Proof'),
        'proof_rejected' => (label: 'Your proof needs another try', group: 'Proof'),
        'crew_request' => (label: 'Crew requests', group: 'Crew'),
        'crew_request_accepted' => (label: 'A request is accepted', group: 'Crew'),
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
          Uri.parse('$_kApiBase/notifications/preferences'),
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
            Uri.parse('$_kApiBase/notifications/preferences'),
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
