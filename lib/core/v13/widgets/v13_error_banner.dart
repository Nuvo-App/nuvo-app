import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_button.dart';
import 'v13_icon_tile.dart';

/// Inline error in the v13 language: a soft coral banner with an icon tile,
/// navy copy and an optional retry. Use wherever a flow surfaces an error
/// in place (never white-on-black).
class V13ErrorBanner extends StatelessWidget {
  const V13ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.error_outline_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(V13.gapMd),
        decoration: BoxDecoration(
          color: V13.coral.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(V13.radiusTileLg),
          border: Border.all(color: V13.coral, width: V13.outline),
        ),
        child: Row(
          children: [
            V13IconTile(icon: icon, color: V13.coral),
            const SizedBox(width: V13.gapMd),
            Expanded(child: Text(message, style: V13.bodyStrong)),
            if (onRetry != null) ...[
              const SizedBox(width: V13.gapSm),
              V13Button.secondary(
                label: retryLabel,
                size: V13ButtonSize.small,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
