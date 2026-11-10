import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';

/// A rotating typewriter headline: types a phrase, holds, backspaces it
/// character by character, then types the next. The box is a fixed two-line
/// height so nothing around it ever shifts. Reduce-motion shows the first
/// phrase static. VoiceOver reads one static label.
class ObTypewriter extends StatefulWidget {
  const ObTypewriter({
    super.key,
    required this.phrases,
    required this.style,
    this.typeChar = NuvoMotion.typeChar,
    this.deleteChar = NuvoMotion.deleteChar,
    this.hold = NuvoMotion.typeHold,
    this.gap = NuvoMotion.typeGap,
    this.semanticLabel,
  });

  final List<String> phrases;
  final TextStyle style;
  final Duration typeChar;
  final Duration deleteChar;
  final Duration hold;
  final Duration gap;
  final String? semanticLabel;

  @override
  State<ObTypewriter> createState() => _ObTypewriterState();
}

enum _Phase { typing, holding, deleting, gap }

class _ObTypewriterState extends State<ObTypewriter> {
  Timer? _timer;
  Timer? _blink;
  int _phrase = 0;
  int _chars = 0;
  _Phase _phase = _Phase.typing;
  bool _cursorOn = true;
  bool _started = false;

  /// What is on screen right now (exposed for tests via the Text widget).
  String get _shown => widget.phrases[_phrase].substring(0, _chars);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _chars = widget.phrases.first.length;
      return;
    }
    _schedule(widget.typeChar);
    _blink = Timer.periodic(NuvoMotion.cursorBlink, (_) {
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blink?.cancel();
    super.dispose();
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _step);
  }

  void _step() {
    if (!mounted) return;
    final full = widget.phrases[_phrase].length;
    setState(() {
      _cursorOn = true;
      switch (_phase) {
        case _Phase.typing:
          _chars++;
          if (_chars >= full) {
            _phase = _Phase.holding;
            _schedule(widget.hold);
          } else {
            _schedule(widget.typeChar);
          }
        case _Phase.holding:
          _phase = _Phase.deleting;
          _schedule(widget.deleteChar);
        case _Phase.deleting:
          _chars--;
          if (_chars <= 0) {
            _chars = 0;
            _phase = _Phase.gap;
            _schedule(widget.gap);
          } else {
            _schedule(widget.deleteChar);
          }
        case _Phase.gap:
          _phrase = (_phrase + 1) % widget.phrases.length;
          _phase = _Phase.typing;
          _schedule(widget.typeChar);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final animated = _blink != null;
    final lineH = (widget.style.fontSize ?? 42) * (widget.style.height ?? 1.1);
    return Semantics(
      label: widget.semanticLabel ?? widget.phrases.first,
      excludeSemantics: true,
      child: SizedBox(
        height: lineH * 2 + 4,
        child: Align(
          alignment: Alignment.topCenter,
          child: Text.rich(
            TextSpan(
              style: widget.style,
              children: [
                TextSpan(text: _shown),
                if (animated)
                  TextSpan(
                    text: '|',
                    style: TextStyle(
                      color: _cursorOn ? null : const Color(0x00000000),
                    ),
                  ),
              ],
            ),
            key: const ValueKey('ob-login-headline'),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
      ),
    );
  }
}
