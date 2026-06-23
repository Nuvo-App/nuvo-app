import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

class PhotoService {
  PhotoService._();

  static const _kNavy = Color(0xFF07152B);
  static const _kBlue = Color(0xFF075BFF);

  /// Pick an image from [source], then present the native crop UI with a
  /// circular guide and 1:1 lock. Returns an [XFile] pointing at the
  /// cropped JPEG, or null if the user cancelled at any step.
  static Future<XFile?> pickAndCrop(ImageSource source) async {
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
      return null;
    }

    if (picked == null) {
      debugPrint('PHOTO_PICK_CANCELLED: user dismissed picker');
      return null;
    }
    debugPrint('PHOTO_PICK_SUCCESS: ${picked.path}');

    // ── Step 2: crop ────────────────────────────────────────────────────────
    debugPrint('PHOTO_CROP_STARTED');
    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        cropStyle: CropStyle.circle,
        aspectRatioPresets: [CropAspectRatioPreset.square],
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Position photo',
            toolbarColor: _kNavy,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _kBlue,
            lockAspectRatio: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
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
      // Crop failed — fall back to raw picked image so the user still gets a preview
      debugPrint('PHOTO_CROP_FALLBACK: using raw picked image');
      return picked;
    }

    if (cropped == null) {
      debugPrint('PHOTO_CROP_CANCELLED: user dismissed cropper');
      return null;
    }
    debugPrint('PHOTO_CROP_SUCCESS: ${cropped.path}');
    return XFile(cropped.path);
  }
}
