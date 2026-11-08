import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/photo_service.dart';
import '../../../../core/v13/v13.dart';
import '../../../auth/data/auth_api.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/profile_v13_api.dart';

/// `/profile/edit` — the v13 editor. Cancel/Done top bar, photo flow, boxed
/// fields (name, username with debounced availability, bio with counter),
/// and favorite-movement chips when the server supports the field.
class EditProfileV13Screen extends ConsumerStatefulWidget {
  const EditProfileV13Screen({super.key});

  @override
  ConsumerState<EditProfileV13Screen> createState() =>
      _EditProfileV13ScreenState();
}

class _EditProfileV13ScreenState extends ConsumerState<EditProfileV13Screen> {
  static const _bioMax = 80;
  static const _movementOptions = [
    ('pushups', 'Pushups'),
    ('squats', 'Squats'),
    ('jumping_jacks', 'Jumping jacks'),
    ('lunges', 'Lunges'),
    ('plank_hold', 'Plank'),
  ];

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  String _initialName = '';
  String _initialUsername = '';
  String _initialBio = '';
  String? _initialMovement;
  String? _favoriteMovement;

  bool _prefsSeeded = false;
  bool _saving = false;
  bool _uploading = false;
  String? _nameError;
  String? _usernameError;

  /// null | 'checking' | 'available' | 'taken' — debounced availability.
  String? _usernameStatus;
  Timer? _debounce;

  bool get _dirty =>
      _nameController.text.trim() != _initialName ||
      _usernameController.text.trim().toLowerCase() != _initialUsername ||
      _bioController.text.trim() != _initialBio ||
      _favoriteMovement != _initialMovement;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _initialName = user?.fullName ?? '';
    _initialUsername = user?.username ?? '';
    _nameController.text = _initialName;
    _usernameController.text = _initialUsername;
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _seedPrefs(NuvoProfilePrefs prefs) {
    if (_prefsSeeded) return;
    _prefsSeeded = true;
    _initialBio = prefs.bio ?? '';
    _initialMovement = prefs.favoriteMovementKey;
    _bioController.text = _initialBio;
    _favoriteMovement = _initialMovement;
  }

  void _onUsernameChanged() {
    _debounce?.cancel();
    final value = _usernameController.text.trim().toLowerCase();
    _usernameError = null;
    if (value.isEmpty || value == _initialUsername) {
      setState(() => _usernameStatus = null);
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final available = await ref
            .read(authControllerProvider.notifier)
            .checkUsername(value);
        if (!mounted) return;
        if (_usernameController.text.trim().toLowerCase() == value) {
          setState(() => _usernameStatus = available ? 'available' : 'taken');
        }
      } catch (_) {
        if (mounted) setState(() => _usernameStatus = null);
      }
    });
  }

  Future<void> _cancel() async {
    if (!_dirty) {
      context.pop();
      return;
    }
    final discard = await showV13ConfirmSheet(
      context,
      title: 'Discard changes?',
      body: 'Your edits won\'t be saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard == true && mounted) context.pop();
  }

  bool _validate() {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name cannot be empty.');
      return false;
    }
    if (username.length < 3) {
      setState(
        () => _usernameError = 'Username must be at least 3 characters.',
      );
      return false;
    }
    if (username.length > 20) {
      setState(
        () => _usernameError = 'Usernames can be at most 20 characters.',
      );
      return false;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(
        () => _usernameError = 'Use only letters, numbers, or underscore.',
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    setState(() {
      _saving = true;
      _nameError = null;
      _usernameError = null;
    });
    try {
      if (username != _initialUsername) {
        final available = await ref
            .read(authControllerProvider.notifier)
            .checkUsername(username);
        if (!available) {
          if (mounted) {
            setState(() => _usernameError = 'That username is already taken.');
          }
          return;
        }
      }
      await ref
          .read(authControllerProvider.notifier)
          .saveProfile(fullName: name, username: username);
      // v13 pref fields ride a separate additive update — the server only
      // touches supplied keys.
      final prefs = ref.read(profilePrefsProvider).valueOrNull;
      if (prefs != null) {
        await ref
            .read(profileV13ApiProvider)
            .updatePrefs(
              bio: prefs.hasBio ? _bioController.text.trim() : null,
              clearBio: prefs.hasBio && _bioController.text.trim().isEmpty,
              favoriteMovementKey: prefs.hasFavoriteMovement
                  ? _favoriteMovement
                  : null,
              clearFavoriteMovement:
                  prefs.hasFavoriteMovement && _favoriteMovement == null,
            );
        ref.invalidate(profilePrefsProvider);
      }
      if (mounted) {
        showV13Toast(context, 'Profile saved.');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _nameError = e.statusCode >= 500
              ? 'Nuvo hit a snag. Try again.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _nameError = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _photoSheet() async {
    final user = ref.read(authControllerProvider).user;
    final hasPhoto = user?.profilePhotoUrl != null;
    final action = await showV13ActionSheet<String>(
      context,
      title: 'Profile photo',
      actions: [
        const V13SheetAction(
          label: 'Choose from photos',
          value: 'gallery',
          icon: Icons.photo_library_rounded,
        ),
        const V13SheetAction(
          label: 'Take photo',
          value: 'camera',
          icon: Icons.photo_camera_rounded,
        ),
        if (hasPhoto)
          const V13SheetAction(
            label: 'Remove photo',
            value: 'remove',
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      final yes = await showV13ConfirmSheet(
        context,
        title: 'Remove photo?',
        confirmLabel: 'Remove',
        destructive: true,
      );
      if (yes != true || !mounted) return;
      setState(() => _uploading = true);
      try {
        await ref.read(authControllerProvider.notifier).removeProfilePhoto();
      } catch (_) {
        if (mounted) {
          showV13Toast(context, "Couldn't remove photo. Try again.");
        }
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }
    await _pickAndUpload(
      action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final result = await ref.read(photoPickerProvider)(source);
    final xFile = result.file;
    if (xFile == null) {
      if (mounted && result.status == PhotoPickStatus.denied) {
        showV13Toast(context, 'Photo access is off. Turn it on in Settings.');
        unawaited(launchUrl(Uri.parse('app-settings:')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(authControllerProvider.notifier).uploadProfilePhoto(xFile);
    } catch (_) {
      if (mounted) {
        showV13Toast(context, "Couldn't upload photo. Try again.");
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profilePrefsProvider, (prev, next) {
      final prefs = next.valueOrNull;
      if (prefs != null && !_prefsSeeded) setState(() => _seedPrefs(prefs));
    });
    final user = ref.watch(authControllerProvider).user;
    final prefs = ref.watch(profilePrefsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V13.pagePad,
                V13.gapMd,
                V13.pagePad,
                V13.gapSm,
              ),
              child: Row(
                children: [
                  V13Button(
                    label: 'Cancel',
                    variant: V13ButtonVariant.ghost,
                    size: V13ButtonSize.small,
                    onPressed: _saving ? null : _cancel,
                  ),
                  Expanded(
                    child: Text(
                      'Edit profile',
                      style: V13.sectionHead,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  V13Button.primary(
                    label: 'Done',
                    size: V13ButtonSize.small,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  V13.pagePad,
                  V13.gapMd,
                  V13.pagePad,
                  V13.gapXxl,
                ),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        V13Face(
                          photoUrl: user?.profilePhotoUrl,
                          size: 96,
                          isMe: true,
                          name: user?.fullName ?? 'You',
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: V13IconButton(
                            icon: _uploading
                                ? Icons.hourglass_top_rounded
                                : Icons.photo_camera_rounded,
                            onTap: _uploading ? null : _photoSheet,
                            semanticLabel: 'Change photo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: V13.gapXl),
                  _field(
                    label: 'NAME',
                    controller: _nameController,
                    error: _nameError,
                    maxLength: 40,
                  ),
                  const SizedBox(height: V13.gapLg),
                  _usernameField(),
                  if (prefs?.hasBio == true) ...[
                    const SizedBox(height: V13.gapLg),
                    _bioField(),
                  ],
                  if (prefs?.hasFavoriteMovement == true) ...[
                    const SizedBox(height: V13.gapLg),
                    Text('FAVORITE MOVEMENT', style: V13.label),
                    const SizedBox(height: V13.gapSm),
                    Wrap(
                      spacing: V13.gapSm,
                      runSpacing: V13.gapSm,
                      children: [
                        for (final (key, label) in _movementOptions)
                          V13Chip(
                            label: label,
                            selected: _favoriteMovement == key,
                            onTap: () => setState(
                              () => _favoriteMovement = _favoriteMovement == key
                                  ? null
                                  : key,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? error,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: V13.label),
        const SizedBox(height: V13.gapSm),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: V13.bodyStrong,
          decoration: _boxedDecoration(error: error),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: V13.gapXs),
            child: Text(error, style: V13.caption.copyWith(color: V13.danger)),
          ),
      ],
    );
  }

  InputDecoration _boxedDecoration({
    String? error,
    Widget? suffix,
    String? hint,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: V13.body.copyWith(color: V13.muted),
      counterText: '',
      filled: true,
      fillColor: V13.card,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: V13.gapLg,
        vertical: V13.gapMd,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(V13.radiusButton),
        borderSide: const BorderSide(color: V13.navy, width: V13.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(V13.radiusButton),
        borderSide: const BorderSide(color: V13.blue, width: V13.outlineThick),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(V13.radiusButton),
        borderSide: const BorderSide(color: V13.danger, width: V13.outline),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(V13.radiusButton),
        borderSide: const BorderSide(
          color: V13.danger,
          width: V13.outlineThick,
        ),
      ),
    );
  }

  Widget _usernameField() {
    Widget? suffix;
    if (_usernameStatus == 'checking') {
      suffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: V13.navy),
        ),
      );
    } else if (_usernameStatus == 'available') {
      suffix = const Icon(Icons.check_circle_rounded, color: V13.mint);
    } else if (_usernameStatus == 'taken') {
      suffix = const Icon(Icons.cancel_rounded, color: V13.danger);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('USERNAME', style: V13.label),
        const SizedBox(height: V13.gapSm),
        TextField(
          controller: _usernameController,
          maxLength: 20,
          style: V13.bodyStrong,
          decoration: _boxedDecoration(
            error: _usernameError,
            suffix: suffix,
            hint: 'username',
          ),
        ),
        if (_usernameError != null)
          Padding(
            padding: const EdgeInsets.only(top: V13.gapXs),
            child: Text(
              _usernameError!,
              style: V13.caption.copyWith(color: V13.danger),
            ),
          )
        else if (_usernameStatus == 'taken')
          Padding(
            padding: const EdgeInsets.only(top: V13.gapXs),
            child: Text(
              'That username is already taken.',
              style: V13.caption.copyWith(color: V13.danger),
            ),
          ),
      ],
    );
  }

  Widget _bioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('BIO', style: V13.label)),
            Text('${_bioController.text.length}/$_bioMax', style: V13.caption),
          ],
        ),
        const SizedBox(height: V13.gapSm),
        TextField(
          controller: _bioController,
          maxLength: _bioMax,
          maxLines: 3,
          minLines: 1,
          style: V13.bodyStrong,
          onChanged: (_) => setState(() {}),
          decoration: _boxedDecoration(hint: 'A line about how you race'),
        ),
      ],
    );
  }
}
