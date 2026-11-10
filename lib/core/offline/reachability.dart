import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../network/api_base.dart';

/// Lightweight "can we reach Nuvo?" signal (no connectivity plugin needed):
/// probes the Worker's `/health`. Probes every [fastEvery] while offline and
/// every [slowEvery] while online. On an offline → online flip it fires
/// [onReconnect] once, so screens refetch and the outbox flushes without a
/// relaunch.
class ReachabilityMonitor extends ChangeNotifier {
  ReachabilityMonitor({
    Future<bool> Function()? probe,
    this.fastEvery = const Duration(seconds: 5),
    this.slowEvery = const Duration(seconds: 30),
  }) : _probe = probe ?? _healthProbe;

  final Future<bool> Function() _probe;
  final Duration fastEvery;
  final Duration slowEvery;

  bool _online = true;
  bool get online => _online;

  /// Called once per offline → online transition.
  Future<void> Function()? onReconnect;

  Timer? _timer;
  bool _checking = false;

  static Future<bool> _healthProbe() async {
    try {
      final res = await http
          .get(Uri.parse('$kNuvoApiBase/health'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Something failed with a network error — switch to fast probing now.
  void reportOffline() {
    if (!_online) return;
    _online = false;
    notifyListeners();
    _schedule();
  }

  /// One probe; flips state and fires [onReconnect] on recovery.
  Future<bool> check() async {
    if (_checking) return _online;
    _checking = true;
    try {
      final ok = await _probe();
      final wasOffline = !_online;
      if (ok != _online) {
        _online = ok;
        notifyListeners();
      }
      if (ok && wasOffline) await onReconnect?.call();
      return ok;
    } finally {
      _checking = false;
      _schedule();
    }
  }

  /// Stops probing (the shell went away); [start] resumes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void start() {
    _schedule();
    unawaited(check());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_online ? slowEvery : fastEvery, () => unawaited(check()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final reachabilityProvider = Provider<ReachabilityMonitor>((ref) {
  final m = ReachabilityMonitor();
  ref.onDispose(m.dispose);
  return m;
});
