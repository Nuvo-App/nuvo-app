import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';

/// One decision per screen, centred: an icon tile, a headline, a short line,
/// optional content, ONE primary action, an optional secondary action, and
/// quiet text links underneath.
///
/// The Teach Nuvo screens use this so every step — intro, learning, result,
/// failure — looks like the same product instead of a form with debug text.
/// Content is vertically centred when it fits and scrolls when it doesn't
/// (small phones, large text), so nothing is ever clipped.
class NuvoFocusedStage extends StatelessWidget {
  const NuvoFocusedStage({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.accent = NuvoColors.blue,
    this.content,
    this.busy = false,
    this.primaryLabel,
    this.onPrimary,
    this.primaryLoading = false,
    this.primaryKey,
    this.secondaryLabel,
    this.onSecondary,
    this.links = const [],
  });

  final String title;
  final String? body;
  final IconData? icon;

  /// Tints the icon tile: blue default, green for done, red for a problem.
  final Color accent;

  /// Extra content between the text and the buttons (steps, a preview, …).
  final Widget? content;

  /// Shows a spinner in place of the icon tile ("Learning…").
  final bool busy;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;

  /// Spotlight key for the first-race coach to point at the primary button.
  final Key? primaryKey;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Quiet text actions pinned to the bottom: ("Change name", onTap).
  final List<(String, VoidCallback?)> links;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final semantic = context.semanticColors;
    final (surface, border) = switch (accent) {
      NuvoColors.success => (semantic.success.surface, semantic.success.border),
      NuvoColors.danger => (semantic.danger.surface, semantic.danger.border),
      NuvoColors.warning => (semantic.warning.surface, semantic.warning.border),
      _ => (semantic.neutral.surface, semantic.neutral.border),
    };

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        else if (icon != null)
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(NuvoRadii.lg),
              border: Border.all(color: border),
            ),
            child: Icon(icon, size: 30, color: accent),
          ),
        if (busy || icon != null) const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: colors.ink,
            height: 1.15,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 10),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: colors.inkMuted),
          ),
        ],
        if (content != null) ...[const SizedBox(height: 22), content!],
      ],
    );

    // The actions are pinned below the scrolling content, never inside it:
    // however tall the content gets (a preview, a long message, big text), the
    // main button stays on screen and tappable.
    final actions = (primaryLabel == null && secondaryLabel == null)
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 6),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (primaryLabel != null)
                      KeyedSubtree(
                        key: primaryKey,
                        child: NuvoPrimaryButton(
                          label: primaryLabel!,
                          expand: true,
                          loading: primaryLoading,
                          onPressed: onPrimary,
                        ),
                      ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(height: 10),
                      NuvoOutlineButton(
                        label: secondaryLabel!,
                        expand: true,
                        onPressed: onSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );

    // Small edit actions ("Change name", "Retry teaching") are plain text at
    // the bottom of the screen, not buttons competing with the main action.
    final linkRow = links.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 14),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < links.length; i++) ...[
                  if (i > 0)
                    Text(
                      '·',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  // Just the text — no button chrome around small edit
                  // actions; they should never read as a second CTA.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: links[i].$2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        links[i].$1,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: colors.inkMuted,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );

    final centred = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (box.maxHeight - 40).clamp(0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: column,
            ),
          ),
        ),
      ),
    );
    return Column(
      children: [
        Expanded(child: centred),
        ?actions,
        if (linkRow != null) linkRow else const SizedBox(height: 14),
      ],
    );
  }
}
