import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens.dart';

OverlayEntry? _activeToast;

/// Small navy pill near the bottom for confirmations — "Joined the race",
/// "Proof logged". Auto-dismisses. A new toast replaces the current one.
void showV13Toast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.of(context);
  _activeToast?.remove();
  _activeToast = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _V13ToastView(
      text: text,
      duration: duration,
      onDone: () {
        if (_activeToast == entry) _activeToast = null;
        entry.remove();
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _V13ToastView extends StatefulWidget {
  const _V13ToastView({
    required this.text,
    required this.duration,
    required this.onDone,
  });

  final String text;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_V13ToastView> createState() => _V13ToastViewState();
}

class _V13ToastViewState extends State<_V13ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 96;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: V13.gapXl,
                  vertical: V13.gapMd,
                ),
                decoration: BoxDecoration(
                  color: V13.navy,
                  borderRadius: BorderRadius.circular(V13.radiusPill),
                ),
                child: Text(
                  widget.text,
                  style: V13.bodyStrong.copyWith(color: V13.card),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
