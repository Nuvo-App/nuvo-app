import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Auth now happens on the welcome screen before onboarding begins.
// This route is a passthrough kept for router continuity.
class SecureAccountScreen extends StatelessWidget {
  const SecureAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/onboarding/profile');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
