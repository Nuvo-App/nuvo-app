import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

class ProofScreen extends StatefulWidget {
  const ProofScreen({super.key, required this.id});

  final String id;

  @override
  State<ProofScreen> createState() => _ProofScreenState();
}

class _ProofScreenState extends State<ProofScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/race/${widget.id}/proof');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: NuvoColors.page,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
