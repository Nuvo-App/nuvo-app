import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource, XFile;

import '../../../core/config/legal_links.dart';
import '../../../core/motion/motion.dart';
import '../../../core/utils/photo_service.dart';
import '../../../core/v13/v13.dart';
import '../../auth/data/auth_api.dart' show ApiException;
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import 'username_rules.dart';

/// Username availability seam — production reads the existing
/// [AuthController.checkUsername]; tests override with a fake.
final obUsernameCheckerProvider =
    Provider<Future<bool> Function(String username)>(
      (ref) => (u) => ref.read(authControllerProvider.notifier).checkUsername(u),
    );

/// The profile write seam — production runs the exact v1 sequence
/// (acceptTerms, attestAge, optional photo upload, saveProfile). Tests
/// override it to record the call.
class ObPlayerProfileSave {
  const ObPlayerProfileSave({
    required this.fullName,
    required this.username,
    this.photo,
  });
  final String fullName;
  final String username;
  final XFile? photo;
}

final obPlayerSaveProvider =
    Provider<Future<void> Function(ObPlayerProfileSave save)>((ref) {
      return (save) async {
        final controller = ref.read(authControllerProvider.notifier);
        await controller.acceptTerms();
        await controller.attestAge();
        if (save.photo != null) {
          try {
            await controller.uploadProfilePhoto(save.photo!);
          } catch (e) {
            // Photo is optional by design: a failed upload never blocks.
            debugPrint('PROFILE_PHOTO_UPLOAD_FAILED: $e');
          }
        }
        await controller.saveProfile(
          fullName: save.fullName,
          username: save.username,
        );
      };
    });

enum _PhotoAction { gallery, camera, remove }

/// S7 — Player card. Live card hero, name + @username (with live
/// availability), optional photo, 13+/terms checkbox, "That's me" (+15 XP).
class ObPlayerCardStep extends ConsumerStatefulWidget {
  const ObPlayerCardStep({super.key});

  @override
  ConsumerState<ObPlayerCardStep> createState() => _ObPlayerCardStepState();
}

class _ObPlayerCardStepState extends ConsumerState<ObPlayerCardStep> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  bool _terms = false;
  bool _saving = false;
  bool? _available;
  bool _checking = false;
  String? _error;
  String? _photoNote;
  Timer? _debounce;

  XFile? _photo;
  Uint8List? _photoBytes;
  int _flip = 0;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _name = TextEditingController(text: user?.fullName ?? '');
    _username = TextEditingController(text: user?.username ?? '');
    _name.addListener(() => setState(() {}));
    _username.addListener(_onUsernameChanged);
    if (_normalized.length >= ObUsernameRules.minLength) _scheduleCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  String get _normalized => ObUsernameRules.normalize(_username.text);

  void _onUsernameChanged() {
    setState(() {
      _available = null;
      _checking = false;
      _error = null;
    });
    _debounce?.cancel();
    final raw = _normalized;
    if (!ObUsernameRules.isValidFormat(raw)) return;
    _scheduleCheck();
  }

  void _scheduleCheck() {
    final raw = _normalized;
    if (!ObUsernameRules.isValidFormat(raw)) return;
    setState(() => _checking = true);
    _debounce = Timer(NuvoMotion.inputDebounce, () async {
      try {
        final ok = await ref.read(obUsernameCheckerProvider)(raw);
        if (mounted && raw == _normalized) {
          setState(() {
            _available = ok;
            _checking = false;
          });
        }
      } catch (_) {
        if (mounted && raw == _normalized) {
          setState(() {
            _checking = false;
            _error =
                "Couldn't check that username. Check your connection and try again.";
          });
        }
      }
    });
  }

  bool get _canContinue =>
      _name.text.trim().isNotEmpty &&
      _available == true &&
      _terms &&
      !_saving;

  // ── Photo ───────────────────────────────────────────────────────────────

  Future<void> _openPhotoSheet() async {
    final action = await showV13ActionSheet<_PhotoAction>(
      context,
      title: 'Profile photo',
      actions: [
        const V13SheetAction(
          label: ObCopy.playerCardPhotoTake,
          icon: Icons.photo_camera_rounded,
          value: _PhotoAction.camera,
        ),
        const V13SheetAction(
          label: ObCopy.playerCardPhotoChoose,
          icon: Icons.photo_library_rounded,
          value: _PhotoAction.gallery,
        ),
        const V13SheetAction(
          label: ObCopy.playerCardPhotoSkip,
          icon: Icons.close_rounded,
          value: _PhotoAction.remove,
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PhotoAction.camera:
        await _pick(ImageSource.camera);
      case _PhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case _PhotoAction.remove:
        setState(() {
          _photo = null;
          _photoBytes = null;
          _photoNote = null;
        });
    }
  }

  Future<void> _pick(ImageSource source) async {
    final result = await ref.read(photoPickerProvider)(source);
    if (!mounted) return;
    final file = result.file;
    if (file == null) {
      setState(() {
        _photoNote = switch (result.status) {
          PhotoPickStatus.denied =>
            'Photo access is off. Turn it on in Settings, or skip this for now.',
          PhotoPickStatus.failed =>
            "Couldn't open photos. You can try again or skip this for now.",
          _ => _photoNote,
        };
      });
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = file;
      _photoBytes = bytes;
      _photoNote = null;
      _flip++;
    });
    NuvoHaptics.medium();
    showV13Confetti(context);
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canContinue) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(obPlayerSaveProvider)(
        ObPlayerProfileSave(
          fullName: _name.text.trim(),
          username: _normalized,
          photo: _photo,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException
              ? (e.statusCode >= 500 ? "Couldn't save. Try again." : e.message)
              : "Couldn't save. Try again.";
        });
      }
      return;
    }
    if (!mounted) return;
    await obAdvance(context, ref, OnboardingStep.playerCard);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  String? get _usernameError {
    final raw = _normalized;
    final fmt = ObUsernameRules.formatError(raw);
    if (fmt != null) return fmt;
    if (_available == false) {
      return '@$raw is ${ObCopy.playerCardUsernameTaken}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final raw = _normalized;
    final taken = _available == false;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return OnboardingShell(
      step: OnboardingStep.playerCard,
      hero: Center(
        child: NuvoFloat(
          child: _PlayerCard(
            name: _name.text.trim(),
            username: raw,
            photoBytes: _photoBytes,
            flip: _flip,
            onPhotoTap: _openPhotoSheet,
          ),
        ),
      ),
      title: ObCopy.playerCardStepCounter,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V13TextInput(
            controller: _name,
            label: ObCopy.playerCardNameField,
            helperText: ObCopy.playerCardNameWhy,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: V13.gapLg),
          V13TextInput(
            controller: _username,
            label: ObCopy.playerCardUsernameField,
            helperText: ObCopy.playerCardUsernameWhy,
            errorText: _usernameError,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 14, right: 4),
              child: Align(
                widthFactor: 1,
                child: Text('@', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            suffixIcon: _checking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : _available == true
                ? const Icon(Icons.check_circle_rounded, color: V13.mint)
                : null,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(ObUsernameRules.maxLength + 1),
            ],
          ),
          if (taken) ...[
            const SizedBox(height: V13.gapSm),
            Wrap(
              spacing: V13.gapSm,
              runSpacing: V13.gapSm,
              children: [
                for (final alt in ObUsernameRules.alternatives(raw))
                  V13Chip(
                    label: ObCopy.playerCardUsernameSuggest(alt),
                    selected: false,
                    onTap: () {
                      NuvoHaptics.select();
                      _username.text = alt;
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: V13.gapLg),
          _PhotoRow(
            hasPhoto: _photoBytes != null,
            note: _photoNote,
            onTap: _openPhotoSheet,
          ),
          const SizedBox(height: V13.gapLg),
          _TermsRow(
            value: _terms,
            onChanged: (v) => setState(() => _terms = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: V13.gapSm),
            Text(
              _error!,
              key: const ValueKey('player-card-error'),
              style: V13.caption.copyWith(
                color: V13.coral,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          // Lets the fields scroll clear of the keyboard (the shell does not
          // resize for it).
          SizedBox(height: keyboard),
        ],
      ),
      ctaLabel: ObCopy.playerCardCta,
      ctaEnabled: _canContinue,
      onCta: _submit,
      onBack: flow.goBack,
    );
  }
}

/// The 300x190 hero card — photo circle left, live name / @username /
/// level pill / tiny XP ring right.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.name,
    required this.username,
    required this.photoBytes,
    required this.flip,
    required this.onPhotoTap,
  });

  final String name;
  final String username;
  final Uint8List? photoBytes;
  final int flip;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final card = Container(
      width: 300,
      height: 190,
      padding: const EdgeInsets.all(V13.gapLg),
      decoration: BoxDecoration(
        color: V13.coral,
        borderRadius: BorderRadius.circular(V13.radiusCard),
        border: Border.all(color: V13.navy, width: V13.outlineThick),
        boxShadow: V13.shadow6,
      ),
      child: Row(
        children: [
          NuvoPressable(
            onTap: onPhotoTap,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            shadow: V13.hardShadow(x: 3, y: 3),
            semanticLabel: 'Add a profile photo',
            child: SizedBox.square(
              dimension: 96,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      key: const ValueKey('player-card-photo'),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: V13.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: V13.navy,
                          width: V13.outlineThick,
                        ),
                      ),
                      child: photoBytes != null
                          ? Image.memory(photoBytes!, fit: BoxFit.cover)
                          : const Icon(
                              Icons.person_rounded,
                              color: V13.muted,
                              size: 56,
                            ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: V13.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: V13.navy, width: V13.outline),
                      ),
                      child: Icon(
                        photoBytes == null
                            ? Icons.add_a_photo_rounded
                            : Icons.edit_rounded,
                        size: 15,
                        color: V13.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? ObCopy.playerCardNameField : name,
                  key: const ValueKey('player-card-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: V13.cardTitle.copyWith(
                    color: name.isEmpty ? V13.navy.withValues(alpha: .45) : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  username.isEmpty ? '@username' : '@$username',
                  key: const ValueKey('player-card-username'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: V13.bodyStrong.copyWith(
                    color: username.isEmpty
                        ? V13.navy.withValues(alpha: .45)
                        : V13.navy,
                  ),
                ),
                const SizedBox(height: V13.gapSm),
                const Row(
                  children: [
                    Flexible(
                      child: V13Pill(
                        label: ObCopy.playerCardLevelPill,
                        color: V13.card,
                      ),
                    ),
                    SizedBox(width: V13.gapSm),
                    V13XpRing(
                      progress: 0.1,
                      size: 30,
                      strokeWidth: 3,
                      name: '',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (reduce || flip == 0) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey(flip),
      tween: Tween(begin: 0, end: 1),
      duration: NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
      builder: (_, t, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(2 * math.pi * t),
        child: child,
      ),
      child: card,
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.hasPhoto,
    required this.note,
    required this.onTap,
  });

  final bool hasPhoto;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NuvoPressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(V13.radiusButton),
          shadow: V13.hardShadow(x: 3, y: 3),
          semanticLabel: 'Profile photo',
          child: Container(
            key: const ValueKey('player-card-photo-row'),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: V13.gapSm,
            ),
            decoration: BoxDecoration(
              color: V13.card,
              borderRadius: BorderRadius.circular(V13.radiusButton),
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            child: Row(
              children: [
                const Icon(Icons.photo_camera_rounded, color: V13.navy),
                const SizedBox(width: V13.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasPhoto ? 'Photo added' : 'Add a photo',
                        style: V13.bodyStrong,
                      ),
                      Text(ObCopy.playerCardPhotoWhy, style: V13.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: V13.muted),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: V13.gapSm),
          Text(
            note!,
            style: V13.caption.copyWith(
              color: V13.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('player-card-terms'),
          onTap: () {
            NuvoHaptics.select();
            onChanged(!value);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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
                    (s) => s.contains(WidgetState.selected) ? V13.blue : null,
                  ),
                  checkColor: V13.card,
                  onChanged: (v) {
                    NuvoHaptics.select();
                    onChanged(v ?? false);
                  },
                ),
                Expanded(
                  child: Text(ObCopy.playerCardTerms, style: V13.body),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Wrap(
            spacing: V13.gapMd,
            children: [
              _LegalLink(label: 'Terms', uri: LegalLinks.termsUri),
              _LegalLink(label: 'Privacy Policy', uri: LegalLinks.privacyUri),
              _LegalLink(
                label: 'Guidelines',
                uri: LegalLinks.communityGuidelinesUri,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openLegalLink(context, uri),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          style: V13.caption.copyWith(
            color: V13.blue,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
