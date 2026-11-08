import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// v13 verification-code input — white boxes with the navy outline, blue
/// while focused. Same interaction contract as the old [OtpInput]: digits
/// advance focus, a pasted run distributes across boxes, backspace on an
/// empty box steps back.
class V13OtpInput extends StatefulWidget {
  const V13OtpInput({super.key, required this.controllers});

  final List<TextEditingController> controllers;

  @override
  State<V13OtpInput> createState() => _V13OtpInputState();
}

class _V13OtpInputState extends State<V13OtpInput> {
  late final List<FocusNode> _nodes = List.generate(
    widget.controllers.length,
    (_) => FocusNode(),
  );

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
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(V13.radiusButton),
      borderSide: BorderSide(color: color, width: V13.outline),
    );
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
              style: V13.sectionHead,
              cursorColor: V13.blue,
              onChanged: (value) => _onChanged(i, value),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: V13.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: border(V13.navy),
                focusedBorder: border(V13.blue),
                errorBorder: border(V13.coral),
              ),
            ),
          ),
          if (i != controllers.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
