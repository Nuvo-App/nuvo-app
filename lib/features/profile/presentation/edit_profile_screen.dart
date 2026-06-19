import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  bool _loading = false;
  String? _nameError;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();

    if (name.isEmpty) {
      setState(() => _nameError = 'Name cannot be empty.');
      return;
    }
    if (username.length < 3) {
      setState(
        () => _usernameError = 'Username must be at least 3 characters.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _nameError = null;
      _usernameError = null;
    });

    try {
      final currentUsername = ref.read(authControllerProvider).user?.username;
      if (username != currentUsername) {
        final available = await ref
            .read(authControllerProvider.notifier)
            .checkUsername(username);
        if (!available && mounted) {
          setState(() {
            _usernameError = 'That username is already taken.';
            _loading = false;
          });
          return;
        }
      }

      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(fullName: name, username: username);

      if (mounted) safePopOrGo(context, '/profile');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _nameError = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _nameError = 'Something went wrong. Try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NuvoBackButton(
                              onPressed: () => safePopOrGo(context, '/profile'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Edit profile',
                            style: AppTextStyles.headlineLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Update your name and username.',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Full name', style: AppTextStyles.titleMedium),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            onChanged: (_) => setState(() => _nameError = null),
                            decoration: _inputDecoration('Your full name'),
                          ),
                          if (_nameError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _nameError!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.red,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text('Username', style: AppTextStyles.titleMedium),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _usernameController,
                            autocorrect: false,
                            onChanged: (_) =>
                                setState(() => _usernameError = null),
                            decoration: _inputDecoration('e.g. akshay'),
                          ),
                          if (_usernameError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _usernameError!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ],
                      )
                      .animate()
                      .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.04,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                expand: true,
                loading: _loading,
                onPressed: _loading ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
    filled: true,
    fillColor: NuvoColors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: NuvoColors.blue, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
