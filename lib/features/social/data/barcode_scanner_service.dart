import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Thin wrapper around ML Kit barcode scanning, restricted to QR codes. Shares
/// the GoogleMLKit 9.x runtime the pose pipeline already ships, and takes the
/// same [InputImage] produced by `camera_image_converter.dart`.
class BarcodeScannerService {
  BarcodeScannerService()
      : _scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  final BarcodeScanner _scanner;
  bool _closed = false;

  /// Returns the first QR payload string in the frame, or null.
  Future<String?> scan(InputImage image) async {
    if (_closed) return null;
    try {
      final codes = await _scanner.processImage(image);
      for (final code in codes) {
        final value = code.rawValue;
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {
      // A single bad frame must never kill the scan loop.
    }
    return null;
  }

  Future<void> dispose() async {
    _closed = true;
    await _scanner.close();
  }
}
