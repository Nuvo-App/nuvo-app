import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while [child] is mounted.
///
/// Verification happens as people do the move — phone propped up, hands busy —
/// so the display must never dim or lock mid-set. Used for every camera route.
///
/// Reference-counted: two overlapping holders (a route replaced by another
/// camera route) never release the lock early, and the lock is released when
/// the last holder goes. Failures (no platform plugin in tests, an OS refusal)
/// are swallowed — keeping the screen awake is a nicety, never a blocker.
class KeepScreenAwake extends StatefulWidget {
  const KeepScreenAwake({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Turn the hold off without unmounting (e.g. while a result sheet is up).
  final bool enabled;

  /// Test seam: replaces the platform call. Receives the desired state.
  @visibleForTesting
  static Future<void> Function(bool enable) setWakelock = _platformSet;

  /// Number of mounted, enabled holders.
  @visibleForTesting
  static int holders = 0;

  static Future<void> _platformSet(bool enable) =>
      WakelockPlus.toggle(enable: enable);

  @override
  State<KeepScreenAwake> createState() => _KeepScreenAwakeState();
}

class _KeepScreenAwakeState extends State<KeepScreenAwake> {
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant KeepScreenAwake oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _sync() => widget.enabled ? _acquire() : _release();

  void _acquire() {
    if (_holding) return;
    _holding = true;
    if (++KeepScreenAwake.holders == 1) _apply(true);
  }

  void _release() {
    if (!_holding) return;
    _holding = false;
    if (--KeepScreenAwake.holders == 0) _apply(false);
  }

  void _apply(bool enable) {
    try {
      KeepScreenAwake.setWakelock(enable).catchError((Object _) {});
    } catch (_) {
      // No platform plugin (tests) or an OS refusal — never block the screen.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
