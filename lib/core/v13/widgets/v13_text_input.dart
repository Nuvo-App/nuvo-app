import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// Labeled text field in the v13 visual language — Manrope label, white
/// fill, 2px navy outline, blue focus ring, coral error ring. The inner
/// [TextField] stays a plain `TextField` so existing finders keep working.
class V13TextInput extends StatelessWidget {
  const V13TextInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofocus = false,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;

  /// Muted guidance below the field (hidden while [errorText] is set).
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool autofocus;
  final bool enabled;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(V13.radiusButton),
      borderSide: const BorderSide(color: V13.navy, width: V13.outline),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: V13.bodyStrong),
          const SizedBox(height: V13.gapSm),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          obscureText: obscureText,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          autofocus: autofocus,
          enabled: enabled,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          style: V13.body,
          cursorColor: V13.blue,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: V13.body.copyWith(color: V13.muted),
            filled: true,
            fillColor: enabled ? V13.card : V13.bg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            enabledBorder: border,
            disabledBorder: border.copyWith(
              borderSide: BorderSide(
                color: V13.navy.withValues(alpha: .35),
                width: V13.outline,
              ),
            ),
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: V13.blue, width: V13.outline),
            ),
            errorBorder: border.copyWith(
              borderSide: const BorderSide(
                color: V13.coral,
                width: V13.outline,
              ),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: const BorderSide(
                color: V13.coral,
                width: V13.outline,
              ),
            ),
            // Errors render below in v13 chrome, not inside the border.
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: V13.caption.copyWith(
              color: V13.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(helperText!, style: V13.caption),
        ],
      ],
    );
  }
}
