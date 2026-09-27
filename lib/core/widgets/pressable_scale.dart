import 'package:flutter/material.dart';

import 'nuvo_motion.dart';

/// Compatibility shim for [NuvoPressable].
///
/// Kept so the existing call sites across cards, rows, chips, and hero
/// surfaces all inherit the shared physical press (translate toward the
/// shadow + spring release) without a per-file migration. New code should
/// use [NuvoPressable] directly.
class PressableScale extends StatelessWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      scale: scale,
      // Silent: PressableScale never fired haptics, and it wraps everything
      // from rows to hero cards — opting all of them into haptics would be
      // spam. Selective haptics belong on NuvoPressable call sites.
      haptic: false,
      child: child,
    );
  }
}
