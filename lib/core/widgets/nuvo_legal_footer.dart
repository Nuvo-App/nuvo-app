import 'package:flutter/material.dart';

import '../config/legal_links.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// "By continuing, you agree to our Terms of Service and Privacy Policy" —
/// the sign-in / sign-up footer. Both links open in the external browser.
class NuvoLegalFooter extends StatelessWidget {
  const NuvoLegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.bodySmall.copyWith(
      color: context.themeColors.inkMuted,
      fontSize: 12,
    );
    return Column(
      children: [
        Text(
          'By continuing, you agree to our',
          textAlign: TextAlign.center,
          style: style,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            NuvoLegalLink(label: 'Terms of Service', uri: LegalLinks.termsUri),
            Text(' and ', style: style),
            NuvoLegalLink(label: 'Privacy Policy', uri: LegalLinks.privacyUri),
          ],
        ),
      ],
    );
  }
}

/// One tappable legal link: blue underlined text on a 44pt-tall target.
/// GestureDetector, never TextButton — the app-level textButtonTheme paints a
/// filled chip behind every TextButton.
class NuvoLegalLink extends StatelessWidget {
  const NuvoLegalLink({
    super.key,
    required this.label,
    required this.uri,
    this.fontSize = 12,
  });

  final String label;
  final Uri uri;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openLegalLink(context, uri),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
