import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource, XFile;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal_links.dart';
import '../../../core/utils/photo_service.dart';
import '../../../core/v13/v13.dart';
import '../../../core/widgets/nuvo_bottom_fade.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../../core/widgets/nuvo_legal_footer.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';

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
  XFile? _pendingImage;
  bool _avatarUploadFailed = false;
  bool _avatarDenied = false;
  String? _avatarError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _nameController.addListener(() => setState(() {}));
    _usernameController.addListener(_onUsernameChanged);
  }

  /// The real reason a username can't be used, or null when the format is
  /// fine. Mirrors the server rule: 3-20 letters, numbers, or underscore.
  static String? _usernameFormatError(String raw) {
    if (raw.length < 3) return null;
    if (RegExp(r'\s').hasMatch(raw)) return "Usernames can't contain spaces.";
    if (raw.length > 20) return 'Usernames can be at most 20 characters.';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(raw)) {
      return 'Use only letters, numbers, or underscore.';
    }
    return null;
  }

  void _onUsernameChanged() {
    setState(() {
      _usernameAvailable = null;
      _usernameChecking = false;
      _error = null;
    });
    _debounce?.cancel();
    final raw = _usernameController.text.trim().toLowerCase();
    if (raw.length < 3 || _usernameFormatError(raw) != null) return;
    setState(() => _usernameChecking = true);
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      try {
        final available = await ref
            .read(authControllerProvider.notifier)
            .checkUsername(raw);
        if (mounted && raw == _usernameController.text.trim().toLowerCase()) {
          setState(() {
            _usernameAvailable = available;
            _usernameChecking = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _usernameChecking = false;
            _error =
                "Couldn't check that username. Check your connection and try again.";
          });
        }
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

  // ── Profile photo ─────────────────────────────────────────────────────────
  // Optional by design — the photo never gates Continue. A denied OS
  // permission explains itself and offers Settings; a failed upload keeps
  // the local preview and shows a retryable error.

  Widget _buildAvatarContent() {
    final remoteUrl = ref.watch(authControllerProvider).user?.profilePhotoUrl;
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
    // v13 people rule: a neutral silhouette, never initials.
    child: const Icon(Icons.person_rounded, color: V13.muted, size: 32),
  );

  Future<void> _openPhotoSheet() async {
    final hasPhoto =
        _pendingImageBytes != null ||
        (ref.read(authControllerProvider).user?.profilePhotoUrl != null);
    final action = await showV13ActionSheet<_PhotoAction>(
      context,
      title: 'Profile photo',
      actions: [
        const V13SheetAction(
          label: 'Choose from photos',
          icon: Icons.photo_library_rounded,
          value: _PhotoAction.gallery,
        ),
        const V13SheetAction(
          label: 'Take photo',
          icon: Icons.photo_camera_rounded,
          value: _PhotoAction.camera,
        ),
        if (hasPhoto)
          const V13SheetAction(
            label: 'Remove photo',
            icon: Icons.delete_outline_rounded,
            value: _PhotoAction.remove,
            destructive: true,
          ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PhotoAction.gallery:
        _pickPhoto(ImageSource.gallery);
      case _PhotoAction.camera:
        _pickPhoto(ImageSource.camera);
      case _PhotoAction.remove:
        _removePhoto();
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
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
      // Local preview only — the actual upload runs on Continue so the
      // server-side terms gate is already satisfied when it fires.
      _pendingImage = xFile;
      _pendingImageBytes = bytes;
      _avatarDenied = false;
      _avatarError = null;
    });
  }

  void _removePhoto() {
    // Nothing has been uploaded during onboarding — removal is local.
    setState(() {
      _pendingImage = null;
      _pendingImageBytes = null;
      _avatarUploadFailed = false;
      _avatarError = null;
      _avatarDenied = false;
    });
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
      // Terms are now recorded server-side, so the avatar upload's terms
      // gate passes. A failed upload keeps the local preview and never
      // blocks Continue — the second press proceeds without it.
      if (_pendingImage != null && !_avatarUploadFailed) {
        try {
          await controller.uploadProfilePhoto(_pendingImage!);
        } catch (e) {
          debugPrint('PROFILE_PHOTO_UPLOAD_FAILED: $e');
          _avatarUploadFailed = true;
          if (mounted) {
            setState(() {
              _avatarError =
                  "Couldn't save your photo. Continue to keep going without it.";
              _loading = false;
            });
          }
          return;
        }
      }
      await controller.saveProfile(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
      );
      if (mounted) context.go('/onboarding/motion-consent');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? (e.statusCode >= 500 ? "Couldn't save. Try again." : e.message)
              : "Couldn't save. Try again.";
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = _usernameController.text.trim();

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: NuvoScrollBottomFade(
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
                                        color: i <= 1 ? V13.blue : V13.divider,
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
                              style: V13.title.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                              ),
                              delay: const Duration(milliseconds: 200),
                              duration: const Duration(milliseconds: 1300),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This is how your friends will see you in races.',
                              style: V13.body.copyWith(
                                color: V13.muted,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Live identity preview — the profile their crew
                            // will see, assembling as they type.
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: V13.card,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: V13.navy, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: V13.navy,
                                    offset: Offset(0, 3),
                                  ),
                                ],
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
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: V13.bg,
                                            border: Border.all(
                                              color: V13.navy,
                                              width: 2,
                                            ),
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
                                            color: V13.blue,
                                            border: Border.all(
                                              color: V13.navy,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: V13.card,
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
                                            _nameController.text.trim().isEmpty
                                                ? 'Your name'
                                                : _nameController.text.trim(),
                                            key: ValueKey(
                                              _nameController.text.trim(),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: V13.bodyStrong.copyWith(
                                              color:
                                                  _nameController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? V13.muted
                                                  : V13.navy,
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
                                          style: V13.body.copyWith(
                                            color: username.isEmpty
                                                ? V13.muted
                                                : V13.blue,
                                            fontWeight: username.isEmpty
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (MediaQuery.sizeOf(context).width >=
                                      360) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: V13.blue.withValues(alpha: .1),
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                          color: V13.blue.withValues(
                                            alpha: .35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'LEVEL 1',
                                        style: V13.label.copyWith(
                                          color: V13.blue,
                                          letterSpacing: 1.4,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
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
                                      style: V13.caption.copyWith(
                                        fontSize: 13,
                                        color: V13.danger,
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
                                          style: V13.caption.copyWith(
                                            fontSize: 13,
                                            color: V13.blue,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),

                            V13TextInput(
                              controller: _nameController,
                              label: 'Full name',
                              hint: 'Your name',
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 16),

                            V13TextInput(
                              controller: _usernameController,
                              label: 'Username',
                              hint: 'handle',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 1,
                                  child: Text('@', style: V13.body),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Username availability feedback
                            if (_usernameChecking)
                              Text(
                                'Checking availability…',
                                style: V13.caption.copyWith(
                                  fontSize: 13,
                                  color: V13.muted,
                                ),
                              )
                            else if (_usernameFormatError(
                                  username.toLowerCase(),
                                ) !=
                                null)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.cancel_rounded,
                                    color: V13.danger,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _usernameFormatError(
                                        username.toLowerCase(),
                                      )!,
                                      style: V13.caption.copyWith(
                                        fontSize: 13,
                                        color: V13.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else if (username.length >= 3) ...[
                              Row(
                                children: [
                                  Icon(
                                    _usernameAvailable == true
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: _usernameAvailable == true
                                        ? V13.blue
                                        : V13.danger,
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
                                      style: V13.caption.copyWith(
                                        fontSize: 13,
                                        color: _usernameAvailable == true
                                            ? V13.blue
                                            : V13.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: V13.caption.copyWith(
                                  fontSize: 13,
                                  color: V13.danger,
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            _ConsentRow(
                              value: _termsAccepted,
                              onChanged: (v) =>
                                  setState(() => _termsAccepted = v),
                              child: Text(
                                "I agree to Nuvo's Terms of Service, "
                                'Privacy Policy and Community Guidelines.',
                                style: V13.caption.copyWith(fontSize: 13),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 48),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  NuvoLegalLink(
                                    label: 'Terms of Service',
                                    uri: LegalLinks.termsUri,
                                    fontSize: 13,
                                  ),
                                  NuvoLegalLink(
                                    label: 'Privacy Policy',
                                    uri: LegalLinks.privacyUri,
                                    fontSize: 13,
                                  ),
                                  NuvoLegalLink(
                                    label: 'Community Guidelines',
                                    uri: LegalLinks.communityGuidelinesUri,
                                    fontSize: 13,
                                  ),
                                ],
                              ),
                            ),
                            _ConsentRow(
                              value: _ageAttested,
                              onChanged: (v) =>
                                  setState(() => _ageAttested = v),
                              child: Text(
                                'I am at least 13 years old.',
                                style: V13.caption.copyWith(fontSize: 13),
                              ),
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
            ),

            // ── Pinned CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: V13Button.primary(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                fullWidth: true,
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

/// A consent checkbox with its label: the box and the text share one
/// vertical centre, the whole row is at least 44pt tall, and tapping the
/// plain text toggles the box (links inside the label keep their own taps).
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox.adaptive(
            value: value,
            side: const BorderSide(color: V13.navy, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            fillColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? V13.blue : null,
            ),
            checkColor: V13.card,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PhotoAction { gallery, camera, remove }
