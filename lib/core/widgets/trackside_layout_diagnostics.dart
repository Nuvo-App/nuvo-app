import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const bool trackSideLayoutDiagnosticsEnabled = bool.fromEnvironment(
  'NUVO_LAYOUT_DIAGNOSTICS',
);

abstract final class TrackSideLayoutKeys {
  static final shell = GlobalKey(debugLabel: 'trackside-shell');
  static final arenaStack = GlobalKey(debugLabel: 'trackside-arena-stack');
  static final arenaScreen = GlobalKey(debugLabel: 'trackside-arena-screen');
  static final canvas = GlobalKey(debugLabel: 'trackside-canvas');
  static final hero = GlobalKey(debugLabel: 'trackside-hero');
  static final panel = GlobalKey(debugLabel: 'trackside-panel');
  static final recentActivity = GlobalKey(debugLabel: 'trackside-recent-activity');
  static final navigation = GlobalKey(debugLabel: 'trackside-navigation');
  static final navigationRow = GlobalKey(debugLabel: 'trackside-navigation-row');
}

abstract final class TrackSideLayoutDiagnostics {
  static final values = ValueNotifier<Map<String, String>>({});

  static void report(Map<String, String> nextValues) {
    if (!trackSideLayoutDiagnosticsEnabled) return;
    final next = <String, String>{...values.value, ...nextValues};
    if (mapEquals(values.value, next)) return;
    values.value = next;
    debugPrint(
      '[NUVO_LAYOUT] ${next.entries.map((entry) => '${entry.key}=${entry.value}').join(' | ')}',
    );
  }

  static String box(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return 'unavailable';
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero));
    return 'top=${topLeft.dy.toStringAsFixed(1)},bottom=${bottomRight.dy.toStringAsFixed(1)},height=${renderObject.size.height.toStringAsFixed(1)},width=${renderObject.size.width.toStringAsFixed(1)}';
  }

  static Map<String, String> viewData(BuildContext context) {
    final view = View.of(context);
    final mediaQuery = MediaQuery.of(context);
    return {
      'marker': 'NUVO_LAYOUT_DIAGNOSTICS=true',
      'physicalSize': '${view.physicalSize.width.toStringAsFixed(1)}x${view.physicalSize.height.toStringAsFixed(1)}',
      'devicePixelRatio': view.devicePixelRatio.toStringAsFixed(3),
      'mediaSize': '${mediaQuery.size.width.toStringAsFixed(1)}x${mediaQuery.size.height.toStringAsFixed(1)}',
      'padding': _edgeInsets(mediaQuery.padding),
      'viewPadding': _edgeInsets(mediaQuery.viewPadding),
    };
  }

  static String _edgeInsets(EdgeInsets value) =>
      'l=${value.left.toStringAsFixed(1)},t=${value.top.toStringAsFixed(1)},r=${value.right.toStringAsFixed(1)},b=${value.bottom.toStringAsFixed(1)}';
}

class TrackSideLayoutDiagnosticsOverlay extends StatelessWidget {
  const TrackSideLayoutDiagnosticsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    if (!trackSideLayoutDiagnosticsEnabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topRight,
          child: ValueListenableBuilder<Map<String, String>>(
            valueListenable: TrackSideLayoutDiagnostics.values,
            builder: (context, values, _) => Container(
              width: 236,
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.all(5),
              color: const Color(0xE6000000),
              child: Text(
                values.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  height: 1.15,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
