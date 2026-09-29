import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_text_styles.dart';

/// Six-box verification code input. Digits typed one at a time advance
/// focus; a pasted/autofilled run of digits distributes across the boxes
/// starting at the focused field; backspace on an empty box steps back.
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.controllers});

  final List<TextEditingController> controllers;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<FocusNode> _nodes =
      List.generate(widget.controllers.length, (_) => FocusNode());

  /// Set while a paste distribute writes sibling controllers — those
  /// writes re-fire onChanged and must not move focus mid-write.
  bool _distributing = false;

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(int i, String value) {
    if (_distributing) return;
    final controllers = widget.controllers;

    // Paste / OTP autofill lands as a multi-char write on one box —
    // distribute the digits across the boxes from this one onward.
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 1) {
      _distributing = true;
      var last = i;
      for (var j = 0; j < digits.length && i + j < controllers.length; j++) {
        controllers[i + j].text = digits[j];
        last = i + j;
      }
      _distributing = false;
      if (last < controllers.length - 1) {
        _nodes[last + 1].requestFocus();
      } else {
        _nodes[last].unfocus();
      }
      return;
    }

    if (value.isNotEmpty) {
      // A stray non-digit or the same digit re-entered — normalize to the
      // digit (or clear) so a box never holds garbage.
      if (value != digits) {
        controllers[i].text = digits;
        if (digits.isEmpty) return;
      }
      if (i < controllers.length - 1) {
        FocusScope.of(context).nextFocus();
      } else {
        _nodes[i].unfocus();
      }
    } else if (i > 0) {
      FocusScope.of(context).previousFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllers = widget.controllers;
    return Row(
      children: [
        for (var i = 0; i < controllers.length; i++) ...[
          Expanded(
            child: TextField(
              controller: controllers[i],
              focusNode: _nodes[i],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              // OneTimeCode hint lets iOS autofill offer the code; the
              // multi-char write it produces is handled by _onChanged.
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTextStyles.headlineMedium.copyWith(
                color: context.themeColors.ink,
              ),
              onChanged: (value) => _onChanged(i, value),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: context.themeColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  borderSide: BorderSide(color: context.themeColors.border),
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
