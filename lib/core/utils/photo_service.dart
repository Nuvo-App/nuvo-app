import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// What happened when the user was sent through the photo picker.
///
/// The distinction matters for UX: a cancel must close silently, a denied
/// permission must explain itself and offer Settings, and a real failure
/// must be recoverable. Collapsing all three into "null" is what made a
/// permission denial look like the button was broken.
enum PhotoPickStatus { picked, cancelled, denied, failed }

class PhotoPickResult {
  const PhotoPickResult._(this.status, this.file);
  const PhotoPickResult.picked(XFile file)
    : this._(PhotoPickStatus.picked, file);
  const PhotoPickResult.cancelled() : this._(PhotoPickStatus.cancelled, null);
  const PhotoPickResult.denied() : this._(PhotoPickStatus.denied, null);
  const PhotoPickResult.failed() : this._(PhotoPickStatus.failed, null);

  final PhotoPickStatus status;
  final XFile? file;
}

/// Injectable pick+edit pipeline — screens read this instead of calling
/// [PhotoService.pickAndCrop] directly so tests can drive every outcome
/// without a platform channel.
final photoPickerProvider =
    Provider<Future<PhotoPickResult> Function(ImageSource)>(
      (_) => PhotoService.pickAndCrop,
    );

class PhotoService {
  PhotoService._();

  static const _kNavy = Color(0xFF07152B);
  static const _kBlue = Color(0xFF075BFF);

  static bool _isPermissionError(Object e) =>
      e is PlatformException &&
      (e.code.contains('denied') || e.code.contains('restricted'));

  /// Pick an image from [source], then present the native crop UI with a
  /// circular guide and 1:1 lock. The result distinguishes a successful
  /// pick (possibly the raw file if the cropper fails), a user cancel at
  /// either step, a denied/restricted OS permission, and a hard failure.
  static Future<PhotoPickResult> pickAndCrop(ImageSource source) async {
    // ── Step 1: pick ────────────────────────────────────────────────────────
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );
    } catch (e) {
      debugPrint('PHOTO_PICK_EXCEPTION: $e');
      return _isPermissionError(e)
          ? const PhotoPickResult.denied()
          : const PhotoPickResult.failed();
    }

    if (picked == null) {
      debugPrint('PHOTO_PICK_CANCELLED: user dismissed picker');
      return const PhotoPickResult.cancelled();
    }
    debugPrint('PHOTO_PICK_SUCCESS: ${picked.path}');

    // ── Step 2: crop ────────────────────────────────────────────────────────
    debugPrint('PHOTO_CROP_STARTED');
    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            cropStyle: CropStyle.circle,
            toolbarTitle: 'Position photo',
            toolbarColor: _kNavy,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _kBlue,
            lockAspectRatio: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
            cropStyle: CropStyle.circle,
            title: 'Position photo',
            doneButtonTitle: 'Use photo',
            cancelButtonTitle: 'Cancel',
            rotateButtonsHidden: true,
            resetAspectRatioEnabled: false,
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('PHOTO_CROP_EXCEPTION: $e');
      // Crop failed — fall back to raw picked image so the user still gets a
      // preview instead of a silent dead end.
      return PhotoPickResult.picked(picked);
    }

    if (cropped == null) {
      debugPrint('PHOTO_CROP_CANCELLED: user dismissed cropper');
      return const PhotoPickResult.cancelled();
    }
    debugPrint('PHOTO_CROP_SUCCESS: ${cropped.path}');
    return PhotoPickResult.picked(XFile(cropped.path));
  }
}
