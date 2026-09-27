import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Character-level "flip" entrance for headline text — a Flutter port of the
/// Vengeance UI `FlipText` component (vengenceui.com/components/flip-text),
/// matching the real implementation's mechanics rather than approximating
/// them with a fade/slide:
///
/// - Every character is a 3D cell inside a 1000px-equivalent perspective
///   (`setEntry(3, 2, 0.001)`). The web version stacks two faces of the same
///   glyph — front at `translateZ(0.6em)`, bottom at
///   `rotateX(-90deg) translateZ(0.6em)` — then rotates the pair
///   `rotateX(0deg → 90deg)` over the first 25% of the cycle: the front face
///   rolls out through the top while the bottom face sweeps in from below
///   along the same 0.6em arc. Here each face's composite transform is
///   `perspective · rotateX(angle) · translateZ(0.6em)`, which reproduces
///   that arc exactly.
/// - Faces crossfade over the first 30% of the cycle (the reference's `fade`
///   keyframes) using `Curves.ease`, which is CSS `ease`.
/// - Per-character delay is the reference's sine stagger —
///   `sin(globalCharIndex / totalChars * pi/2) * duration * 0.25` — early
///   characters bunch together and later ones spread out, producing the
///   wave rather than a linear cascade.
/// - Played once ([loop] false), the text is absent before its pass and only
///   the incoming face animates — that arc sweep IS the entrance. With
///   [loop] true the full two-face cycle runs continuously, matching the
///   component's infinite mode (outgoing face rolls up and away as the
///   incoming face lands, then the cycle snaps back — invisible because
///   both faces draw the same glyph).
///
/// Honors `MediaQuery.disableAnimationsOf` (renders plain text) and exposes
/// the full string to semantics — per-character `Text` widgets would
/// otherwise read as single letters to screen readers.
class NuvoFlipText extends StatefulWidget {
  const NuvoFlipText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.duration = const Duration(milliseconds: 1600),
    this.delay = Duration.zero,
    this.staggered = true,
    this.loop = false,
    this.play = true,
    this.replayOnTextChange = true,
    this.onCompleted,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Length of one character's flip cycle — the reference's `duration`.
  /// The rotation occupies the first 25%, the face crossfade the first 30%,
  /// and the stagger window is 25%, so [duration] also scales the wave.
  final Duration duration;

  /// Idle time before the first character starts — the reference's `delay`.
  final Duration delay;

  /// When false every character starts together — the reference's
  /// `together` prop.
  final bool staggered;

  /// When true the two-face flip cycle repeats indefinitely like the
  /// reference's `loop` mode. When false (the default) the text flips in
  /// once and holds its settled state.
  final bool loop;

  /// When false the text stays hidden (play-once) or at rest (loop) until
  /// [play] becomes true. The animation also starts automatically on mount
  /// when this is true.
  final bool play;

  /// Replays the entrance when [text] genuinely changes.
  final bool replayOnTextChange;

  /// Called once when a play-once pass fully settles. Never fires for
  /// [loop] mode, and still fires (on the first frame) under reduced motion
  /// so sequenced UI isn't gated on motion the user can't see.
  final VoidCallback? onCompleted;

  /// Overrides the semantics label; defaults to [text].
  final String? semanticsLabel;

  @override
  State<NuvoFlipText> createState() => _NuvoFlipTextState();
}

class _NuvoFlipTextState extends State<NuvoFlipText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  bool _started = false;
  bool _completedFired = false;
  bool _reducedMotion = false;

  double get _cycleMs => widget.duration.inMilliseconds.toDouble();

  /// The reference staggers within `duration * 0.25`.
  double get _staggerSpanMs => _cycleMs * 0.25;

  /// Play-once horizon: every character has started AND settled. The last
  /// character's face crossfade ends at start + 30% of its cycle (rotation
  /// is done by 25%), so the remainder of [duration] is invisible tail.
  Duration get _runDuration => Duration(
    milliseconds:
        (widget.delay.inMilliseconds + _staggerSpanMs + _cycleMs * 0.3)
            .round(),
  );

  @override
  void initState() {
    super.initState();
    // A raw Ticker (not an AnimationController) because looping mode needs
    // monotonically increasing elapsed time: each character's phase is
    // `(elapsed - start) mod cycle`, which a sawtooth controller value
    // can't express across repeats.
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant NuvoFlipText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.replayOnTextChange) {
      _restart();
      return;
    }
    if (widget.play && !oldWidget.play) {
      _maybeStart();
    } else if (!widget.play && oldWidget.play) {
      // Withdrawn mid-flight: stop and reset so the next play is a clean
      // entrance rather than a resume.
      _ticker.stop();
      _started = false;
      _elapsed = Duration.zero;
    }
  }

  void _maybeStart() {
    if (!widget.play) return;
    if (_reducedMotion) {
      _completeOnNextFrame();
      return;
    }
    if (_started) return;
    _started = true;
    _ticker.start();
  }

  void _restart() {
    _ticker.stop();
    _elapsed = Duration.zero;
    _started = false;
    _completedFired = false;
    _maybeStart();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final finished = !widget.loop && elapsed >= _runDuration;
    if (_elapsed != elapsed) setState(() => _elapsed = elapsed);
    if (finished) {
      _ticker.stop();
      if (!_completedFired) {
        _completedFired = true;
        widget.onCompleted?.call();
      }
    }
  }

  /// Reduced-motion completion: the text renders statically, but sequenced
  /// parents still need their "text is done" signal.
  void _completeOnNextFrame() {
    if (widget.loop || _completedFired) return;
    _completedFired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCompleted?.call();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// One character's position in its cycle: `-1` before it starts
  /// (hidden for play-once, at rest for loop), `0→1` while animating, `1`
  /// once settled.
  double _charPhase(int globalIndex, int totalChars, double elapsedMs) {
    final startMs =
        widget.delay.inMilliseconds.toDouble() +
        (widget.staggered
            ? math.sin((globalIndex / totalChars) * math.pi / 2) *
                _staggerSpanMs
            : 0.0);
    final raw = (elapsedMs - startMs) / _cycleMs;
    if (widget.loop) return raw < 0 ? -1.0 : raw % 1.0;
    return raw < 0 ? -1.0 : raw.clamp(0.0, 1.0);
  }

  Widget _face(
    String char,
    TextStyle style,
    double angle,
    double opacity,
    double radius,
  ) {
    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(angle)
          ..translateByDouble(0.0, 0.0, -radius, 1.0),
        child: Text(char, style: style),
      ),
    );
  }

  Widget _buildChar(
    String char,
    TextStyle style,
    int globalIndex,
    int totalChars,
    double elapsedMs,
    double cellHeight,
    double radius,
  ) {
    final phase = _charPhase(globalIndex, totalChars, elapsedMs);
    // Reference keyframes: rotateX over 0–25% of the cycle, opacity over
    // 0–30%, both with CSS `ease` (== Curves.ease).
    final rotP = phase <= 0
        ? 0.0
        : (phase >= 0.25 ? 1.0 : Curves.ease.transform(phase / 0.25));
    final fadeP = phase <= 0
        ? 0.0
        : (phase >= 0.30 ? 1.0 : Curves.ease.transform(phase / 0.30));

    // Incoming (bottom) face: sweeps up from edge-on below to flat. Flutter's
    // z convention is the mirror of CSS (with entry(3,2)=0.001, +z recedes),
    // so the reference's -90deg→0 / +z becomes +90deg→0 / -z here — the
    // vertical arc is identical, and "toward the viewer" still magnifies.
    final inAngle = lerpDouble(math.pi / 2, 0, rotP)!;
    // Outgoing (front) face, loop mode only: rolls out through the top.
    final outAngle = lerpDouble(0, -math.pi / 2, rotP)!;

    return SizedBox(
      height: cellHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.loop) _face(char, style, outAngle, 1 - fadeP, radius),
          _face(char, style, inAngle, fadeP, radius),
        ],
      ),
    );
  }

  WrapAlignment get _wrapAlignment => switch (widget.textAlign) {
    TextAlign.center => WrapAlignment.center,
    TextAlign.right || TextAlign.end => WrapAlignment.end,
    _ => WrapAlignment.start,
  };

  CrossAxisAlignment get _crossAlignment => switch (widget.textAlign) {
    TextAlign.center => CrossAxisAlignment.center,
    TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.start,
  };

  double _measureSpace(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(
      context,
    ).style.merge(widget.style);

    if (_reducedMotion) {
      return Text(
        widget.text,
        style: effectiveStyle,
        textAlign: widget.textAlign,
      );
    }
    if (widget.text.isEmpty) return const SizedBox.shrink();

    final fontSize = effectiveStyle.fontSize ?? 14.0;
    // Reference cell geometry: height/line-height 1.2em, faces pushed out
    // 0.6em, wrapper leading-none (so runs touch — runSpacing stays 0).
    final cellHeight = fontSize * 1.2;
    final radius = fontSize * 0.6;
    final spaceWidth = _measureSpace(effectiveStyle);
    final elapsedMs = _elapsed.inMicroseconds / 1000.0;
    final totalChars = widget.text.length;

    final lines = <Widget>[];
    var globalIndex = 0;
    final textLines = widget.text.split('\n');
    for (var li = 0; li < textLines.length; li++) {
      // Words are `inline-block whitespace-nowrap` in the reference — each
      // is an unbreakable Row; wrapping happens only between words.
      final words = textLines[li].split(' ');
      final wordWidgets = <Widget>[];
      for (var wi = 0; wi < words.length; wi++) {
        // Grapheme clusters keep multi-code-unit glyphs (emoji, accents)
        // in one cell instead of shattering them across faces.
        final cells = <Widget>[];
        for (final char in words[wi].characters) {
          cells.add(
            _buildChar(
              char,
              effectiveStyle,
              globalIndex,
              totalChars,
              elapsedMs,
              cellHeight,
              radius,
            ),
          );
          // JS counts UTF-16 code units; Characters gives clusters —
          // char.length restores the reference's index accounting.
          globalIndex += char.length;
        }
        wordWidgets.add(
          Row(mainAxisSize: MainAxisSize.min, children: cells),
        );
        if (wi < words.length - 1) globalIndex += 1; // the space separator
      }
      lines.add(
        Wrap(
          alignment: _wrapAlignment,
          spacing: spaceWidth,
          children: wordWidgets,
        ),
      );
      globalIndex += 1; // the newline separator between lines
    }

    return Semantics(
      label: widget.semanticsLabel ?? widget.text,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _crossAlignment,
          children: lines,
        ),
      ),
    );
  }
}
