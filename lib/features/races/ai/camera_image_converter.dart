import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class CameraImageConversionException implements Exception {
  const CameraImageConversionException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

InputImage inputImageFromCameraImage({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  final rotation = _rotationForCamera(
    camera: camera,
    deviceOrientation: deviceOrientation,
  );
  if (rotation == null) {
    throw const CameraImageConversionException(
      'Camera rotation is not supported for this frame.',
    );
  }

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null ||
      (Platform.isAndroid && format != InputImageFormat.nv21) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888)) {
    throw CameraImageConversionException(
      'Camera frame format ${image.format.group.name} is not supported.',
    );
  }

  if (image.planes.length != 1) {
    throw CameraImageConversionException(
      'Expected one camera image plane, received ${image.planes.length}.',
    );
  }

  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

InputImageRotation? _rotationForCamera({
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  final sensorOrientation = camera.sensorOrientation;
  if (Platform.isIOS) {
    return InputImageRotationValue.fromRawValue(sensorOrientation);
  }
  if (!Platform.isAndroid) {
    return InputImageRotationValue.fromRawValue(sensorOrientation);
  }

  var rotationCompensation = _orientations[deviceOrientation];
  if (rotationCompensation == null) return null;

  if (camera.lensDirection == CameraLensDirection.front) {
    rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
  } else {
    rotationCompensation =
        (sensorOrientation - rotationCompensation + 360) % 360;
  }
  return InputImageRotationValue.fromRawValue(rotationCompensation);
}
