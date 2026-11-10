import 'package:flutter/material.dart';

/// The real Nuvo app icon (the brand's own blue tile with the M), flat on
/// the page: no shadow, no tilt, no float. The email/code header.
class ObBrandMark extends StatelessWidget {
  const ObBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final room = c.maxHeight.isFinite ? c.maxHeight : 88.0;
        final side = (room - 8).clamp(0.0, 88.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(side * 0.225),
            child: Image.asset(
              'assets/branding/nuvo_app_icon.png',
              key: const ValueKey('ob-brand-mark'),
              width: side,
              height: side,
              fit: BoxFit.cover,
              semanticLabel: 'Nuvo',
              errorBuilder: (_, _, _) => SizedBox.square(dimension: side),
            ),
          ),
        );
      },
    );
  }
}
