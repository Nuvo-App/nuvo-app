import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_button.dart';
import 'v13_list_row.dart';
import 'v13_pressable.dart';

/// The v13 bottom sheet: rounded top, navy outline, drag handle.
Future<T?> showV13Sheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: V13.navy.withValues(alpha: 0.45),
    builder: (ctx) => _V13SheetFrame(child: builder(ctx)),
  );
}

class _V13SheetFrame extends StatelessWidget {
  const _V13SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.viewInsetsOf(context);
    final safe = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: view.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(V13.radiusCardLg),
          ),
          border: Border.fromBorderSide(
            BorderSide(color: V13.navy, width: V13.outline),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: V13.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(child: child),
            SizedBox(height: safe.bottom),
          ],
        ),
      ),
    );
  }
}

/// Title + body + Cancel/confirm. [destructive] renders the confirm in red.
/// Resolves true on confirm, false on cancel, null on dismiss.
Future<bool?> showV13ConfirmSheet(
  BuildContext context, {
  required String title,
  String? body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) {
  return showV13Sheet<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V13.sectionHead),
          if (body != null) ...[
            const SizedBox(height: V13.gapSm),
            Text(body, style: V13.body.copyWith(color: V13.muted)),
          ],
          const SizedBox(height: V13.gapXl),
          Row(
            children: [
              Expanded(
                child: V13Button.secondary(
                  label: cancelLabel,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: V13.gapMd),
              Expanded(
                child: V13Button(
                  variant: destructive
                      ? V13ButtonVariant.danger
                      : V13ButtonVariant.primary,
                  label: confirmLabel,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One action row inside [showV13ActionSheet].
class V13SheetAction<T> {
  const V13SheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final T value;
  final IconData? icon;

  /// Red label — remove, leave, block, report.
  final bool destructive;
}

/// Action list sheet — the 3-dot menus. Resolves the tapped action's value;
/// null on cancel/dismiss.
Future<T?> showV13ActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<V13SheetAction<T>> actions,
  String cancelLabel = 'Cancel',
}) {
  return showV13Sheet<T>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: V13.gapSm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: V13.gapMd),
              child: Text(title.toUpperCase(), style: V13.label),
            ),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const V13Divider(),
            V13Pressable(
              onTap: () => Navigator.of(ctx).pop(actions[i].value),
              pressDepth: 1.5,
              semanticLabel: actions[i].label,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V13.pagePad,
                  vertical: V13.gapLg,
                ),
                child: Row(
                  children: [
                    if (actions[i].icon != null) ...[
                      Icon(
                        actions[i].icon,
                        size: 20,
                        color: actions[i].destructive ? V13.danger : V13.navy,
                      ),
                      const SizedBox(width: V13.gapMd),
                    ],
                    Expanded(
                      child: Text(
                        actions[i].label,
                        style: V13.bodyStrong.copyWith(
                          color: actions[i].destructive ? V13.danger : V13.navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const V13Divider(),
          V13Pressable(
            onTap: () => Navigator.of(ctx).pop(),
            pressDepth: 1.5,
            semanticLabel: cancelLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V13.pagePad,
                vertical: V13.gapLg,
              ),
              child: Center(child: Text(cancelLabel, style: V13.bodyStrong)),
            ),
          ),
        ],
      ),
    ),
  );
}
