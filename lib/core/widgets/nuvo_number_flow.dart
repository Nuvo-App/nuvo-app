import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Direction the digit wheels travel when [NuvoNumberFlow.value] changes.
enum NuvoNumberFlowTrend {
  /// Derive direction from the numeric change; equal values fall back to
  /// each digit's shortest roll.
  auto,

  /// Always roll upward, odometer-style.
  increasing,

  /// Always roll downward.
  decreasing,
}

enum _CellKind { digit, literal }

/// One position in the rendered string: either a single digit (keyed by its
/// digit-run index and place within the run) or a run of non-digit
/// characters (a decimal point, " min ", etc.) keyed by its literal index.
class _CellSpec {
  const _CellSpec.digitCell(this.key, this.digit)
    : kind = _CellKind.digit,
      text = null;

  const _CellSpec.literalCell(this.key, this.text)
    : kind = _CellKind.literal,
      digit = -1;

  final _CellKind kind;
  final Object key;
  final int digit;
  final String? text;
}

class _Cell {
  _Cell(this.spec);

  final _CellSpec spec;

  /// Wheel start-offset for the in-flight transition: the cell's virtual
  /// scroll position renders as `digit - animDelta * (1 - eased)`.
  double animDelta = 0;

  /// Frozen wheel position for an exiting cell.
  double frozenC = 0;

  bool entering = false;
  bool exiting = false;

  /// Literal crossfade source when the text at this position changed.
  String? fadeFromText;
}

/// Per-digit rolling number — a Flutter port of the digit-level transition
/// in `@number-flow/react` (the engine behind skiper-ui.com/v1/skiper37):
///
/// - The formatted value is split into cells: one per digit, one per run of
///   non-digit characters (a decimal point, " min ", etc.).
/// - Each digit cell is a wheel of 0–9 whose virtual scroll position is
///   `digit - animDelta`. Every glyph positions itself by its signed mod-10
///   offset from that position, so a roll passes through the intermediate
///   digits instead of crossfading (`4 → 7` sweeps past 5 and 6).
/// - On change, each surviving cell animates `animDelta → 0` from wherever
///   the wheel currently sits, so rapid taps converge on the latest value
///   instead of queueing animations.
/// - Roll direction follows the value's trend: increases roll up, decreases
///   roll down, and a wrap (`9 → 0` on +1) keeps rolling the same way.
/// - Digits in the first run align by place from the right, so a growing
///   number (`9 → 10`) inserts a leading cell that fades and expands in
///   rather than re-rolling the existing leading digit; later runs
///   (fraction digits) align from the left so appended digits grow right.
/// - Cells whose place index is unchanged never move.
///
/// Honors `MediaQuery.disableAnimationsOf` (renders plain text) and exposes
/// the full string to semantics — per-cell `Text` widgets would otherwise
/// read as single digits to screen readers.
class NuvoNumberFlow extends StatefulWidget {
  const NuvoNumberFlow({
    super.key,
    required this.value,
    this.format,
    this.trend = NuvoNumberFlowTrend.auto,
    this.style,
    this.textAlign = TextAlign.start,
    this.duration = const Duration(milliseconds: 260),
    this.curve = const Cubic(0.22, 1, 0.36, 1),
    this.semanticsLabel,
  });

  /// The value to display — the source of truth. Animation is purely
  /// presentational and never delays the underlying value.
  final int value;

  /// Optional formatter (metres → "0.25", seconds → "1 min 20 sec").
  /// Defaults to `'$value'`.
  final String Function(int value)? format;

  /// Roll direction; [NuvoNumberFlowTrend.auto] derives it from the sign of
  /// the numeric change.
  final NuvoNumberFlowTrend trend;

  final TextStyle? style;
  final TextAlign textAlign;

  /// Length of one transition. Re-taps restart it from the wheel's current
  /// position rather than queueing.
  final Duration duration;

  /// Shared easing for every cell — a strong ease-out so the first frames
  /// move visibly and the settle has almost no bounce.
  final Curve curve;

  /// Overrides the semantics label; defaults to the formatted text.
  final String? semanticsLabel;

  @override
  State<NuvoNumberFlow> createState() => _NuvoNumberFlowState();
}

class _NuvoNumberFlowState extends State<NuvoNumberFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Cell> _cells;
  late String _currentText;
  bool _reducedMotion = false;

  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  double _cellW = 0;
  double _lineH = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener(_onStatus);
    _currentText = _text(widget.value);
    _cells = [for (final spec in _parse(_currentText)) _Cell(spec)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant NuvoNumberFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ctrl.duration = widget.duration;
    final nextText = _text(widget.value);
    if (nextText == _currentText) return;
    if (_reducedMotion) {
      _currentText = nextText;
      _cells = [for (final spec in _parse(nextText)) _Cell(spec)];
      return;
    }
    _transition(nextText, widget.value - oldWidget.value);
    _currentText = nextText;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _text(int value) => widget.format?.call(value) ?? '$value';

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _cells.any((cell) => cell.exiting)) {
      setState(() => _cells.removeWhere((cell) => cell.exiting));
    }
  }

  /// Split into per-digit and per-literal cells. The first digit run keys
  /// cells from the right (place value) so growth inserts on the left; later
  /// runs key from the left so fraction growth appends on the right.
  static List<_CellSpec> _parse(String s) {
    bool isDigit(int j) {
      final u = s.codeUnitAt(j);
      return u >= 0x30 && u <= 0x39;
    }

    final specs = <_CellSpec>[];
    var runIndex = -1;
    var literalIndex = 0;
    var i = 0;
    while (i < s.length) {
      if (isDigit(i)) {
        runIndex++;
        var j = i;
        while (j < s.length && isDigit(j)) {
          j++;
        }
        final alignRight = runIndex == 0;
        final len = j - i;
        for (var k = 0; k < len; k++) {
          final place = alignRight ? len - 1 - k : k;
          specs.add(
            _CellSpec.digitCell(
              (runIndex, place),
              s.codeUnitAt(i + k) - 0x30,
            ),
          );
        }
        i = j;
      } else {
        var j = i;
        while (j < s.length && !isDigit(j)) {
          j++;
        }
        specs.add(
          _CellSpec.literalCell(('l', literalIndex), s.substring(i, j)),
        );
        literalIndex++;
        i = j;
      }
    }
    return specs;
  }

  /// Choose the roll distance (in wheel steps) that lands on the target,
  /// mirroring NumberFlow's trend-aware delta: up rolls stay positive, down
  /// rolls stay negative, auto takes the shortest path. A near-full rotation
  /// means the wheel is a fraction of a step away — settle through the short
  /// wrap instead of spinning the whole reel.
  static double _pickDelta(double d, int trend) {
    var r = d % 10.0;
    if (trend < 0 && r != 0) r -= 10;
    if (trend == 0 && r > 5) r -= 10;
    if (r > 9) r -= 10;
    if (r < -9) r += 10;
    return r;
  }

  /// Signed mod-10 offset of glyph [n] from scroll position [c], in
  /// (-5, 5]. 0 centers the glyph; +1 parks it one line below.
  static double _signedOffset(int n, double c) {
    final raw = (n - c) % 10.0;
    return raw >= 5 ? raw - 10 : raw;
  }

  void _transition(String nextText, int delta) {
    final eased = widget.curve.transform(_ctrl.value.clamp(0.0, 1.0));
    final trend = switch (widget.trend) {
      NuvoNumberFlowTrend.increasing => 1,
      NuvoNumberFlowTrend.decreasing => -1,
      NuvoNumberFlowTrend.auto => delta.sign,
    };

    final oldCells = _cells;
    final live = [for (final c in oldCells) if (!c.exiting) c];
    final unmatched = <Object, _Cell>{for (final c in live) c.spec.key: c};

    // Freeze each live wheel at its current visual position — the starting
    // point for the next roll, which is what makes mid-flight re-taps
    // continuous instead of snapping.
    final visualC = <_Cell, double>{};
    for (final c in live) {
      if (c.spec.kind == _CellKind.digit) {
        visualC[c] = c.spec.digit - c.animDelta * (1 - eased);
      }
    }

    final migrated = <_Cell, _Cell>{};
    final next = <_Cell>[];
    for (final spec in _parse(nextText)) {
      final prev = unmatched.remove(spec.key);
      final cell = _Cell(spec);
      if (spec.kind == _CellKind.digit) {
        if (prev != null) {
          cell.animDelta = _pickDelta(spec.digit - visualC[prev]!, trend);
          migrated[prev] = cell;
        } else {
          // A brand-new cell rolls a single step in the direction of
          // travel while it fades and expands in.
          cell.entering = true;
          cell.animDelta = trend >= 0 ? 1.0 : -1.0;
        }
      } else {
        if (prev != null) {
          if (prev.spec.text != spec.text) cell.fadeFromText = prev.spec.text;
          migrated[prev] = cell;
        } else {
          cell.entering = true;
        }
      }
      next.add(cell);
    }

    // Unmatched survivors exit near their original position; ordering stays
    // monotonic with their old indices so multiple exits keep their order.
    var insertPos = 0;
    for (var i = 0; i < oldCells.length; i++) {
      final old = oldCells[i];
      if (old.exiting || !unmatched.containsValue(old)) continue;
      old
        ..exiting = true
        ..frozenC = visualC[old] ?? 0;
      var pos = insertPos;
      for (var j = i - 1; j >= 0; j--) {
        final moved = migrated[oldCells[j]];
        if (moved != null) {
          pos = math.max(next.indexOf(moved) + 1, insertPos);
          break;
        }
      }
      next.insert(pos.clamp(0, next.length), old);
      insertPos = pos + 1;
    }

    _cells = next;
    _ctrl.forward(from: 0);
  }

  /// Fixed cell metrics: every digit cell takes the widest glyph's width so
  /// `9 → 10` and `99 → 100` add a column instead of re-laying out the row.
  void _measure(TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    if (_measuredStyle == style && _measuredScaler == scaler) return;
    var w = 0.0;
    var h = 0.0;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    for (var n = 0; n < 10; n++) {
      final painter = TextPainter(
        text: TextSpan(text: '$n', style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      w = math.max(w, painter.width);
      h = math.max(h, painter.height);
      painter.dispose();
    }
    _cellW = w;
    _lineH = h;
    _measuredStyle = style;
    _measuredScaler = scaler;
  }

  Widget _digitWheel(double c, TextStyle style) {
    return SizedBox(
      width: _cellW,
      height: _lineH,
      child: ClipRect(
        child: Stack(
          children: [
            for (var n = 0; n < 10; n++)
              Transform.translate(
                offset: Offset(0, _signedOffset(n, c) * _lineH),
                child: Opacity(
                  opacity: (1.4 - _signedOffset(n, c).abs()).clamp(0.0, 1.0),
                  child: Align(child: Text('$n', style: style)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _literalContent(_Cell cell, double eased, TextStyle style) {
    final text = cell.spec.text!;
    final from = cell.fadeFromText;
    if (from == null || from == text) {
      return Text(text, style: style, softWrap: false, maxLines: 1);
    }
    return Stack(
      children: [
        Opacity(
          opacity: 1 - eased,
          child: Text(from, style: style, softWrap: false, maxLines: 1),
        ),
        Opacity(
          opacity: eased,
          child: Text(text, style: style, softWrap: false, maxLines: 1),
        ),
      ],
    );
  }

  Widget _buildCell(_Cell cell, double eased, TextStyle style) {
    final widthFactor = cell.exiting
        ? 1 - eased
        : cell.entering
        ? eased
        : 1.0;
    final fade = cell.exiting
        ? 1 - eased
        : cell.entering
        ? eased
        : 1.0;

    Widget content;
    if (cell.spec.kind == _CellKind.digit) {
      final c = cell.exiting
          ? cell.frozenC
          : cell.spec.digit - cell.animDelta * (1 - eased);
      content = _digitWheel(c, style);
    } else {
      content = _literalContent(cell, eased, style);
    }

    if (widthFactor != 1 || fade != 1) {
      content = ClipRect(
        child: Align(
          widthFactor: widthFactor.clamp(0.0, 1.0),
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: content,
          ),
        ),
      );
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);

    if (_reducedMotion) {
      return Text(
        _currentText,
        style: style,
        textAlign: widget.textAlign,
        semanticsLabel: widget.semanticsLabel,
      );
    }

    _measure(style);

    return Semantics(
      label: widget.semanticsLabel ?? _currentText,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final eased = widget.curve.transform(_ctrl.value);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cell in _cells) _buildCell(cell, eased, style),
              ],
            );
          },
        ),
      ),
    );
  }
}
