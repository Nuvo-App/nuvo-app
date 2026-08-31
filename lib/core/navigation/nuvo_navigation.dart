import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pops the current route if possible; otherwise goes to [fallback].
/// Use this for all manually-placed back buttons to prevent "nothing to pop" crashes.
void safePopOrGo(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
