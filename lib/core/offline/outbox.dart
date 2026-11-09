import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/data/auth_api.dart' show ApiException;

/// A network failure the outbox may retry: Nuvo unreachable (status 0) or a
/// timeout (408). Anything else is a real server answer and is not retried.
bool isNetworkFailure(Object e, {bool includeTimeout = true}) =>
    e is ApiException &&
    (e.statusCode == 0 || (includeTimeout && e.statusCode == 408));

/// Thrown to the UI when an action was saved to the outbox instead of sent:
/// the message reads as a calm "saved, will send" rather than an error.
class OfflineQueuedException extends ApiException {
  const OfflineQueuedException()
    : super(
        -1,
        'No connection — saved. We’ll send it when you’re back online.',
      );
}

/// One queued outgoing action. [id] is its idempotency key: enqueueing the
/// same id twice keeps a single entry.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.kind,
    required this.payload,
    this.attempts = 0,
    DateTime? nextAttemptAt,
    DateTime? createdAt,
  }) : nextAttemptAt = nextAttemptAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String kind;
  final Map<String, dynamic> payload;
  int attempts;
  DateTime nextAttemptAt;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'payload': payload,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  static OutboxEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], kind = j['kind'], payload = j['payload'];
    if (id is! String || kind is! String || payload is! Map) return null;
    return OutboxEntry(
      id: id,
      kind: kind,
      payload: Map<String, dynamic>.from(payload),
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: DateTime.tryParse('${j['nextAttemptAt']}'),
      createdAt: DateTime.tryParse('${j['createdAt']}'),
    );
  }
}

typedef OutboxHandler = Future<void> Function(Map<String, dynamic> payload);

/// Persistent queue of outgoing actions that failed for lack of network.
/// Flushes on demand (launch, resume, a periodic tick while non-empty);
/// retries with exponential backoff; drops an entry when the server gives a
/// real (non-network) answer, or after [maxAttempts].
class Outbox extends ChangeNotifier {
  Outbox({this.memoryOnly = false, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// In-memory store for tests — never touches disk.
  Outbox.memory({DateTime Function()? now}) : this(memoryOnly: true, now: now);

  final bool memoryOnly;
  final DateTime Function() _now;
  final List<OutboxEntry> _entries = [];
  final Map<String, OutboxHandler> _handlers = {};
  bool _loaded = false;
  bool _flushing = false;

  /// Last flush outcome: false after a network failure, true after a
  /// successful send. Null before anything was tried.
  bool? lastReachable;

  static const int maxAttempts = 12;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);
  int get pendingCount => _entries.length;

  void registerHandler(String kind, OutboxHandler handler) =>
      _handlers[kind] = handler;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (memoryOnly) return;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString());
      if (list is List) {
        _entries.addAll(list.map(OutboxEntry.fromJson).whereType<OutboxEntry>());
      }
    } catch (_) {
      // A corrupt outbox must never block launch.
    }
    notifyListeners();
  }

  /// Like [enqueue] but the newest entry for [entry.id] wins (e.g. the
  /// latest reaction on one item).
  Future<void> upsert(OutboxEntry entry) async {
    await load();
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.add(entry);
    lastReachable = false;
    await _persist();
    notifyListeners();
  }

  Future<void> enqueue(OutboxEntry entry) async {
    await load();
    if (_entries.any((e) => e.id == entry.id)) return; // idempotent
    _entries.add(entry);
    lastReachable = false;
    await _persist();
    notifyListeners();
  }

  /// Backoff: 5 s, 10 s, 20 s … capped at 10 min.
  Duration backoffFor(int attempts) {
    final secs = 5 * (1 << attempts.clamp(0, 7));
    return Duration(seconds: secs > 600 ? 600 : secs);
  }

  /// Sends every due entry in order. Returns how many were sent.
  Future<int> flush({bool force = false}) async {
    await load();
    if (_flushing || _entries.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final e in List.of(_entries)) {
        if (!force && e.nextAttemptAt.isAfter(_now())) continue;
        final handler = _handlers[e.kind];
        if (handler == null) continue;
        try {
          await handler(e.payload);
          _entries.remove(e);
          sent++;
          lastReachable = true;
        } catch (err) {
          if (isNetworkFailure(err) && e.attempts + 1 < maxAttempts) {
            e.attempts++;
            e.nextAttemptAt = _now().add(backoffFor(e.attempts));
            lastReachable = false;
            // Still offline — no point hammering the rest this round.
            break;
          }
          // A real server answer (or out of attempts): drop it.
          _entries.remove(e);
        }
      }
    } finally {
      _flushing = false;
      await _persist();
      notifyListeners();
    }
    return sent;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_outbox.json');
  }

  Future<void> _persist() async {
    if (memoryOnly) return;
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

final outboxProvider = Provider<Outbox>((ref) {
  final o = Outbox();
  ref.onDispose(o.dispose);
  return o;
});
