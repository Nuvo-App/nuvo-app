import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';

class OtpInput extends StatelessWidget {
  const OtpInput({super.key, required this.controllers});

  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < controllers.length; i++) ...[
          Expanded(
            child: TextField(
              controller: controllers[i],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.navy,
              ),
              onChanged: (value) {
                if (value.isNotEmpty && i < controllers.length - 1) {
                  FocusScope.of(context).nextFocus();
                }
                if (value.isEmpty && i > 0) {
                  FocusScope.of(context).previousFocus();
                }
              },
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: NuvoColors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  borderSide: const BorderSide(color: NuvoColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  borderSide: const BorderSide(
                    color: NuvoColors.blue,
                    width: 1.8,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  borderSide: const BorderSide(color: NuvoColors.danger),
                ),
              ),
            ),
          ),
          if (i != controllers.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
