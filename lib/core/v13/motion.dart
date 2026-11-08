import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// v13 motion language — one spring curve, three durations.
///
/// Spec: "one overshoot spring curve for presses, the tab indicator,
/// toggles and number pops (about 420 to 600 ms). Buttons press by sinking
/// into their shadow, with a light haptic."
abstract final class V13Motion {
  /// The single overshoot curve. easeOutBack-shaped with ~10% overshoot —
  /// a playful settle without a wobble.
  static const Curve spring = _V13SpringCurve();

  /// Standard spring move — toggles, chip selection, indicator hops.
  static const Duration fast = Duration(milliseconds: 420);

  /// Default settle — tab indicator, segmented control, sheets.
  static const Duration medium = Duration(milliseconds: 520);

  /// Longest move — number pops, larger indicator travel.
  static const Duration slow = Duration(milliseconds: 600);

  /// Finger-down response — fast enough to feel instant.
  static const Duration pressIn = Duration(milliseconds: 80);
}

class _V13SpringCurve extends Curve {
  const _V13SpringCurve();

  @override
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // easeOutBack family: 1 + (c+1)·u³ + c·u² with u = t−1.
    // c = 1.70158 peaks at ~1.10 — the v13 "just past" overshoot.
    const c = 1.70158;
    final u = t - 1;
    return 1 + (c + 1) * u * u * u + c * u * u;
  }
}

/// Install-scoped haptics preference for the v13 shell.
///
/// Same storage approach as [NuvoThemeModeStore]: a small JSON file in the
/// app documents directory, loaded once at launch, in-memory state
/// authoritative for the session. Persist failure just reverts the choice —
/// never crashes.
class V13HapticsStore {
  V13HapticsStore() : _memoryOnly = false;

  /// In-memory store for tests — never touches disk.
  V13HapticsStore.memory() : _memoryOnly = true;

  final bool _memoryOnly;
  final List<void Function()> _listeners = [];
  bool _loaded = false;
  bool _enabled = true;

  bool get enabled => _enabled;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (_memoryOnly) return;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['enabled'] == false) {
        _enabled = false;
      }
    } catch (_) {
      // Corrupt/unreadable file falls back to enabled.
    }
  }

  Future<void> set(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    if (_memoryOnly) return;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'enabled': enabled}));
    } catch (_) {
      // Persistence failure is not worth a crash.
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nuvo_v13_haptics.json');
  }
}

final _v13HapticsStore = V13HapticsStore();

/// Called from main() before runApp alongside `ensureNuvoThemeModeLoaded`
/// so the first frame already honors the saved preference.
Future<void> ensureV13HapticsLoaded() => _v13HapticsStore.ensureLoaded();

/// Settings surface for the haptics toggle.
Future<void> setV13HapticsEnabled(bool enabled) =>
    _v13HapticsStore.set(enabled);

/// Reactive read of the pref — Settings rows watch this.
final v13HapticsEnabledProvider = Provider<bool>((ref) {
  void changed() => ref.invalidateSelf();
  _v13HapticsStore.addListener(changed);
  ref.onDispose(() => _v13HapticsStore.removeListener(changed));
  return _v13HapticsStore.enabled;
});

/// v13 haptic vocabulary — every call is gated on the local pref.
abstract final class V13Haptics {
  static bool get _on => _v13HapticsStore.enabled;

  /// Physical presses — buttons, tappable cards, toggles.
  static void light() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// Selection changes — tabs, chips, segmented controls.
  static void select() {
    if (_on) HapticFeedback.selectionClick();
  }

  /// Meaningful confirmations — proof logged, request accepted.
  static void confirm() {
    if (_on) HapticFeedback.mediumImpact();
  }
}


/// First-load list entrance: fade + rise, staggered by [index]. The delay is
/// capped so a long list never waits on its tail, and it plays once per
/// mounted element (scrolling back doesn't replay it). Respects reduced
/// motion.
class V13StaggerIn extends StatefulWidget {
  const V13StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<V13StaggerIn> createState() => _V13StaggerInState();
}

class _V13StaggerInState extends State<V13StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQueryData.fromView(View.of(context)).disableAnimations) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}
