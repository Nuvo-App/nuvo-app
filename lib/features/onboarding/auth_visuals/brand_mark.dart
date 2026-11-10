import 'package:flutter/material.dart';

/// The real Nuvo logo (navy variant, blue dot) flat on the white
/// top section — the same mark as the login, left-aligned as the email/code
/// header. No tile, no shadow, no tilt, no float.
class ObBrandMark extends StatelessWidget {
  const ObBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final room = c.maxHeight.isFinite ? c.maxHeight : 88.0;
        return Align(
          alignment: Alignment.bottomLeft,
          child: Image.asset(
            'assets/branding/nuvo_logo_navy.png',
            key: const ValueKey('ob-brand-mark'),
            height: (room - 12).clamp(0.0, 84.0),
            fit: BoxFit.contain,
            semanticLabel: 'Nuvo',
            errorBuilder: (_, _, _) => SizedBox(height: room),
          ),
        );
      },
    );
  }
}
