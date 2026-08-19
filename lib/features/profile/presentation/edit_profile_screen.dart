import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/photo_service.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
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
  bool _uploading = false;
  Uint8List? _pendingImageBytes;
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

  // ── Single entry point for all photo tap targets ──────────────────────────

  void _openProfilePhotoSheet() {
    debugPrint('PROFILE_PHOTO_SHEET_OPENED');
    final hasPhoto =
        (ref.read(authControllerProvider).user?.profilePhotoUrl != null) ||
        _pendingImageBytes != null;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: NuvoColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Profile photo', style: AppTextStyles.titleLarge),
              const SizedBox(height: 16),
              _EditSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from photos',
                onTap: () {
                  debugPrint('PROFILE_PHOTO_CHOOSE_FROM_PHOTOS');
                  Navigator.of(sheetCtx).pop();
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              _EditSheetOption(
                icon: Icons.photo_camera_rounded,
                label: 'Take photo',
                onTap: () {
                  debugPrint('PROFILE_PHOTO_TAKE_PHOTO');
                  Navigator.of(sheetCtx).pop();
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 8),
                _EditSheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  isDestructive: true,
                  onTap: () {
                    debugPrint('PROFILE_PHOTO_REMOVE_PHOTO');
                    Navigator.of(sheetCtx).pop();
                    _confirmAndRemove();
                  },
                ),
              ],
              const SizedBox(height: 8),
              _EditSheetOption(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    debugPrint('PHOTO_PICK_STARTED');
    final xFile = await PhotoService.pickAndCrop(source);
    if (xFile == null) {
      debugPrint('PHOTO_PICK_CANCELLED');
      return;
    }
    if (!mounted) return;
    debugPrint('PHOTO_PICK_SUCCESS');

    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    debugPrint('PENDING_IMAGE_BYTES_SET: ${bytes.length} bytes');
    setState(() {
      _uploading = true;
      _pendingImageBytes = bytes;
    });

    debugPrint('PROFILE_PHOTO_UPLOAD_STARTED');
    try {
      await ref.read(authControllerProvider.notifier).uploadProfilePhoto(xFile);
      debugPrint('PROFILE_PHOTO_UPLOAD_SUCCESS');
    } catch (e) {
      debugPrint('PROFILE_PHOTO_UPLOAD_FAILED: $e');
      // Keep pending preview visible; show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't upload photo. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmAndRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text("You'll go back to your initials."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: NuvoColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _uploading = true;
      _pendingImageBytes = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).removeProfilePhoto();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    debugPrint('EDIT_PROFILE_SAVE_TAPPED');
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
    debugPrint('EDIT_PROFILE_SAVE_STARTED');

    try {
      final currentUsername = ref.read(authControllerProvider).user?.username;
      if (username != currentUsername) {
        final available = await ref
            .read(authControllerProvider.notifier)
            .checkUsername(username);
        if (!available && mounted) {
          setState(() => _usernameError = 'That username is already taken.');
          return;
        }
      }

      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(fullName: name, username: username);
      debugPrint('EDIT_PROFILE_SAVE_SUCCESS');

      if (mounted) {
        debugPrint('EDIT_PROFILE_NAVIGATE_PROFILE');
        context.go('/profile');
      }
    } on ApiException catch (e) {
      debugPrint('EDIT_PROFILE_SAVE_FAILED: ${e.message}');
      if (mounted) {
        setState(() {
          _nameError = e.statusCode >= 500
              ? 'Nuvo hit a snag. Try again.'
              : 'Could not save your changes. Try again.';
        });
      }
    } catch (e) {
      debugPrint('EDIT_PROFILE_SAVE_FAILED: $e');
      if (mounted) {
        setState(() => _nameError = 'Something went wrong. Try again.');
      }
    } finally {
      debugPrint('EDIT_PROFILE_LOADING_RESET');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final photoUrl = user?.profilePhotoUrl;
    final initials = user?.avatarInitials ?? '?';
    final hasPhoto = photoUrl != null || _pendingImageBytes != null;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  ListView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
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
                            style: AppTextStyles.headlineLarge.copyWith(
                              fontSize: 32,
                              letterSpacing: -0.9,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Update your photo, name, and username.',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: NuvoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Photo section ──────────────────────────────────────────
                          Center(
                            child: Column(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _uploading
                                      ? null
                                      : () {
                                          debugPrint(
                                            'EDIT_PROFILE_AVATAR_TAPPED',
                                          );
                                          _openProfilePhotoSheet();
                                        },
                                  child: SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _uploading
                                            ? Container(
                                                width: 88,
                                                height: 88,
                                                decoration: BoxDecoration(
                                                  color: NuvoColors.navy
                                                      .withValues(alpha: 0.08),
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                        color: NuvoColors.blue,
                                                      ),
                                                ),
                                              )
                                            : NuvoAvatar(
                                                initials: initials,
                                                localBytes: _pendingImageBytes,
                                                photoUrl: photoUrl,
                                                size: 88,
                                                bgColor: NuvoColors.navy
                                                    .withValues(alpha: 0.08),
                                                textColor: NuvoColors.navy,
                                              ),
                                        if (!_uploading)
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                debugPrint(
                                                  'EDIT_PROFILE_BADGE_TAPPED',
                                                );
                                                _openProfilePhotoSheet();
                                              },
                                              child: Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color: NuvoColors.blue,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: NuvoColors.page,
                                                    width: 2,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  hasPhoto
                                                      ? Icons.edit_rounded
                                                      : Icons
                                                            .photo_camera_rounded,
                                                  color: NuvoColors.white,
                                                  size: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _uploading
                                      ? null
                                      : () {
                                          debugPrint(
                                            'EDIT_PROFILE_ADD_PHOTO_TAPPED',
                                          );
                                          _openProfilePhotoSheet();
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      hasPhoto ? 'Change photo' : 'Add photo',
                                      style: AppTextStyles.labelMedium.copyWith(
                                        color: NuvoColors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                          NuvoTextInput(
                            controller: _nameController,
                            label: 'Full name',
                            hint: 'Your full name',
                            errorText: _nameError,
                            onChanged: (_) => setState(() => _nameError = null),
                          ),
                          const SizedBox(height: 16),
                          NuvoTextInput(
                            controller: _usernameController,
                            label: 'Username',
                            hint: 'e.g. akshay',
                            errorText: _usernameError,
                            onChanged: (_) =>
                                setState(() => _usernameError = null),
                          ),
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
}

// ── Sheet option ──────────────────────────────────────────────────────────────

class _EditSheetOption extends StatelessWidget {
  const _EditSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? NuvoColors.danger : NuvoColors.navy;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDestructive
              ? NuvoColors.danger.withValues(alpha: 0.05)
              : NuvoColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDestructive
                ? NuvoColors.danger.withValues(alpha: 0.20)
                : NuvoColors.navy,
            width: isDestructive ? 1 : 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.bodyMedium.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
