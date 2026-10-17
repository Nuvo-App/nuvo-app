import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps a screen's data fresh without the user closing and reopening the app.
///
/// Calls [onRefresh] when the app returns to the foreground and, while the
/// screen is actually showing (not an off-stage tab, not backgrounded), on a
/// quiet [interval]. [onRefresh] should be cheap and conditional — the
/// controllers' own single-flight and ETag handling keep repeated calls light.
class LiveRefresh extends StatefulWidget {
  const LiveRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.interval = const Duration(seconds: 20),
  });

  final VoidCallback onRefresh;
  final Duration interval;
  final Widget child;

  @override
  State<LiveRefresh> createState() => _LiveRefreshState();
}

class _LiveRefreshState extends State<LiveRefresh> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Off-stage tabs keep their state alive but have tickers disabled; that is
  /// the signal this screen is not the one being looked at.
  bool get _visible => mounted && TickerMode.valuesOf(context).enabled;

  void _tick() {
    if (_foreground && _visible) widget.onRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _visible) widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
