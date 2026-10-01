import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/photo_service.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/presentation/auth_controller.dart';

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  bool _termsAccepted = false;
  bool _ageAttested = false;
  bool _loading = false;
  bool? _usernameAvailable;
  bool _usernameChecking = false;
  String? _error;
  Timer? _debounce;

  // Avatar pipeline state — four distinct things, never conflated:
  // the local selection preview, the saved remote URL (read from the user
  // model), the in-flight upload, and the last picker/upload problem.
  Uint8List? _pendingImageBytes;
  bool _uploadingAvatar = false;
  bool _avatarDenied = false;
  String? _avatarError;

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _nameController.addListener(() => setState(() {}));
    _usernameController.addListener(_onUsernameChanged);
  }

  void _onUsernameChanged() {
    setState(() {
      _usernameAvailable = null;
      _error = null;
    });
    _debounce?.cancel();
    final raw = _usernameController.text.trim().toLowerCase();
    if (raw.length < 3) return;
    setState(() => _usernameChecking = true);
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      final available = await ref
          .read(authControllerProvider.notifier)
          .checkUsername(raw);
      if (mounted) {
        setState(() {
          _usernameAvailable = available;
          _usernameChecking = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String get _initials {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) return '?';
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // ── Profile photo ─────────────────────────────────────────────────────────
  // Optional by design — the photo never gates Continue. A denied OS
  // permission explains itself and offers Settings; a failed upload keeps
  // the local preview and shows a retryable error.

  Widget _buildAvatarContent() {
    final remoteUrl = ref
        .watch(authControllerProvider)
        .user
        ?.profilePhotoUrl;
    // Priority: freshly picked local bytes > saved remote photo > initials.
    if (_pendingImageBytes != null) {
      return Image.memory(
        _pendingImageBytes!,
        key: const ValueKey('avatar-local'),
        fit: BoxFit.cover,
        width: 64,
        height: 64,
      );
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return Image.network(
        remoteUrl,
        key: const ValueKey('avatar-remote'),
        fit: BoxFit.cover,
        width: 64,
        height: 64,
        errorBuilder: (_, _, _) => _avatarInitials(),
      );
    }
    return _avatarInitials();
  }

  Widget _avatarInitials() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .7, end: 1).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      _initials,
      key: ValueKey(_initials),
      style: AppTextStyles.titleLarge.copyWith(
        color: NuvoColors.white,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  void _openPhotoSheet() {
    final hasPhoto =
        _pendingImageBytes != null ||
        (ref.read(authControllerProvider).user?.profilePhotoUrl != null);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: NuvoColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text('Profile photo', style: AppTextStyles.titleLarge),
              const SizedBox(height: 16),
              _PhotoSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from photos',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              _PhotoSheetOption(
                icon: Icons.photo_camera_rounded,
                label: 'Take photo',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 8),
                _PhotoSheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  isDestructive: true,
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _removePhoto();
                  },
                ),
              ],
              const SizedBox(height: 8),
              _PhotoSheetOption(
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
    final result = await ref.read(photoPickerProvider)(source);
    if (!mounted) return;
    final xFile = result.file;
    if (xFile == null) {
      // Cancel closes silently. Denied explains itself and offers Settings.
      // A hard failure says so — never a silent dead button.
      setState(() {
        _avatarDenied = result.status == PhotoPickStatus.denied;
        _avatarError = switch (result.status) {
          PhotoPickStatus.denied =>
            'Photo access is off. Turn it on in Settings to add a photo.',
          PhotoPickStatus.failed =>
            "Couldn't open photos. You can try again or skip this for now.",
          _ => _avatarError,
        };
      });
      return;
    }

    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() {
      // Local preview lands immediately — the avatar shows the pick before
      // the upload round-trips.
      _pendingImageBytes = bytes;
      _uploadingAvatar = true;
      _avatarDenied = false;
      _avatarError = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .uploadProfilePhoto(xFile);
    } catch (e) {
      debugPrint('PROFILE_PHOTO_UPLOAD_FAILED: $e');
      if (mounted) {
        setState(() {
          // Keep the local preview; the photo is retryable and optional.
          _avatarError =
              "Couldn't upload photo. Tap your photo to try again, or continue without it.";
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() {
      _uploadingAvatar = true;
      _pendingImageBytes = null;
      _avatarError = null;
      _avatarDenied = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).removeProfilePhoto();
    } catch (_) {
      if (mounted) {
        setState(
          () => _avatarError = "Couldn't remove photo. Please try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty &&
      _usernameController.text.trim().length >= 3 &&
      _usernameAvailable == true &&
      _termsAccepted &&
      _ageAttested &&
      !_loading;

  Future<void> _continue() async {
    if (!_termsAccepted) {
      setState(
        () => _error = 'Please accept the Terms of Service to continue.',
      );
      return;
    }
    if (!_ageAttested) {
      setState(
        () => _error = 'Please confirm you are at least 13 to continue.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      await controller.acceptTerms();
      await controller.attestAge();
      await controller.saveProfile(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
      );
      if (mounted) context.go('/onboarding/motion-consent');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is Exception
              ? e.toString()
              : 'Could not save profile. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = _usernameController.text.trim();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child:
                  SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Step progress (3 steps: race, profile, pass)
                            Row(
                              children: [
                                for (var i = 0; i < 3; i++) ...[
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: i <= 1
                                            ? NuvoColors.blue
                                            : NuvoColors.border,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                  if (i < 2) const SizedBox(width: 4),
                                ],
                              ],
                            ),
                            const SizedBox(height: 24),

                            NuvoFlipText(
                              'Build your profile',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                                color: NuvoColors.navy,
                              ),
                              delay: const Duration(milliseconds: 200),
                              duration: const Duration(milliseconds: 1300),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This is how your crew will see you in races.',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Live identity preview — the profile their crew
                            // will see, assembling as they type.
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: NuvoColors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: NuvoColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    key: const ValueKey('onboarding-avatar'),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _openPhotoSheet,
                                    child: Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: NuvoColors.navy,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          alignment: Alignment.center,
                                          child: _buildAvatarContent(),
                                        ),
                                        Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: NuvoColors.blue,
                                            border: Border.all(
                                              color: NuvoColors.page,
                                              width: 2,
                                            ),
                                          ),
                                          child: _uploadingAvatar
                                              ? const Padding(
                                                  padding: EdgeInsets.all(3),
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            NuvoColors.white,
                                                      ),
                                                    )
                                              : const Icon(
                                                  Icons.camera_alt_rounded,
                                                  color: NuvoColors.white,
                                                  size: 12,
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          child: Text(
                                            _nameController.text
                                                    .trim()
                                                    .isEmpty
                                                ? 'Your name'
                                                : _nameController.text.trim(),
                                            key: ValueKey(
                                              _nameController.text.trim(),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.titleMedium
                                                .copyWith(
                                                  color:
                                                      _nameController.text
                                                          .trim()
                                                          .isEmpty
                                                      ? NuvoColors.muted
                                                      : NuvoColors.navy,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          username.isEmpty
                                              ? '@handle'
                                              : '@$username',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: username.isEmpty
                                                    ? NuvoColors.muted
                                                    : NuvoColors.blue,
                                                fontWeight: username.isEmpty
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: NuvoColors.blue.withValues(
                                        alpha: .1,
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: NuvoColors.blue.withValues(
                                          alpha: .35,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'LEVEL 1',
                                      style: AppTextStyles.brandLabel.copyWith(
                                        color: NuvoColors.blue,
                                        letterSpacing: 1.4,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ).animate().fadeIn(
                                  delay: const Duration(milliseconds: 350),
                                  duration: const Duration(milliseconds: 400),
                                ),

                            if (_avatarError != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _avatarError!,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: NuvoColors.danger,
                                      ),
                                    ),
                                  ),
                                  if (_avatarDenied)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          launchUrl(Uri.parse('app-settings:')),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Open Settings',
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                color: NuvoColors.blue,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),

                            NuvoTextInput(
                              controller: _nameController,
                              label: 'Full name',
                              hint: 'Your name',
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 16),

                            NuvoTextInput(
                              controller: _usernameController,
                              label: 'Username',
                              hint: 'handle',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 1,
                                  child: Text(
                                    '@',
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Username availability feedback
                            if (_usernameChecking)
                              Text(
                                'Checking availability…',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.muted,
                                ),
                              )
                            else if (username.length >= 3) ...[
                              Row(
                                children: [
                                  Icon(
                                    _usernameAvailable == true
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: _usernameAvailable == true
                                        ? NuvoColors.success
                                        : NuvoColors.danger,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _usernameAvailable == true
                                          ? '@$username is available'
                                          : '@$username is taken',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: _usernameAvailable == true
                                            ? NuvoColors.success
                                            : NuvoColors.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 20),

                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.danger,
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox.adaptive(
                                  value: _termsAccepted,
                                  fillColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.selected)
                                        ? NuvoColors.blue
                                        : null,
                                  ),
                                  onChanged: (value) => setState(
                                    () => _termsAccepted = value ?? false,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 8,
                                    ),
                                    child: RichText(
                                      text: TextSpan(
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: NuvoColors.muted,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'I agree to the ',
                                          ),
                                          TextSpan(
                                            text: 'Terms of Service',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: NuvoColors.blue,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () =>
                                                  _openLegalUrl(_kTermsUrl),
                                          ),
                                          const TextSpan(text: ' and '),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: NuvoColors.blue,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () =>
                                                  _openLegalUrl(_kPrivacyUrl),
                                          ),
                                          const TextSpan(text: '.'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox.adaptive(
                                  value: _ageAttested,
                                  fillColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.selected)
                                        ? NuvoColors.blue
                                        : null,
                                  ),
                                  onChanged: (value) => setState(
                                    () => _ageAttested = value ?? false,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 8,
                                    ),
                                    child: Text(
                                      'I am at least 13 years old.',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: NuvoColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

            // ── Pinned CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                loading: _loading,
                onPressed: _canContinue ? _continue : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the profile-photo source sheet — same shape as the edit
/// profile sheet options (fixed-height row, panel fill, leading icon).
class _PhotoSheetOption extends StatelessWidget {
  const _PhotoSheetOption({
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
              : NuvoColors.page,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDestructive
                ? NuvoColors.danger.withValues(alpha: 0.20)
                : NuvoColors.border,
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
