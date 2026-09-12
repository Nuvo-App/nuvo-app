import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../races/ai/camera_image_converter.dart';
import '../data/barcode_scanner_service.dart';
import '../domain/nuvo_destination.dart';

/// `/scan` — the in-app QR scanner. Only ever acts on a **Nuvo** link
/// (`NuvoDestination.tryParse` returns non-null); anything else shows
/// "This isn't a Nuvo code." and keeps scanning. Never opens an arbitrary URL.
/// Always previews before joining/connecting — it routes to the same
/// `NuvoDestination` flow as every other entry source (deep link, push).
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

enum _ScanState { starting, scanning, permissionDenied, noCamera, error }

class _QrScanScreenState extends ConsumerState<QrScanScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  final _scanner = BarcodeScannerService();
  final _pasteController = TextEditingController();

  _ScanState _state = _ScanState.starting;
  String? _errorText;
  bool _processing = false;
  bool _handled = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    _pasteController.dispose();
    _camera?.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _state == _ScanState.permissionDenied) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _state = _ScanState.starting;
      _errorText = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _state = _ScanState.noCamera);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _camera?.dispose();
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      _camera = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) return;
      setState(() => _state = _ScanState.scanning);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted';
      setState(() {
        _state = denied ? _ScanState.permissionDenied : _ScanState.error;
        _errorText = denied ? null : (e.description ?? e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorText = '$e';
      });
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _handled) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame) < const Duration(milliseconds: 250)) return;
    _lastFrame = now;
    _processing = true;
    try {
      final input = inputImageFromCameraImage(
        image: image,
        camera: _camera!.description,
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      final raw = await _scanner.scan(input);
      if (raw != null && mounted) _consider(raw);
    } catch (_) {
      // frame conversion hiccup — ignore
    } finally {
      _processing = false;
    }
  }

  void _consider(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final dest = uri == null ? null : NuvoDestination.tryParse(uri);
    if (dest == null) {
      _showToast("That isn't a Nuvo code.");
      return;
    }
    _handled = true;
    HapticFeedback.mediumImpact();
    _camera?.stopImageStream().catchError((_) {});
    // Same destination model as every other entry source. An invite destination
    // is `/invite/:token`, which previews before it joins — the scanner never
    // acts on a code by itself. Replace the scanner so Back doesn't return to a
    // stopped camera.
    if (mounted) context.pushReplacement(dest.location);
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _submitPasted() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;
    _consider(text);
    if (!_handled) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Navy chrome, not black — the camera preview itself is the only
      // legitimately black surface (a live feed, not a fill choice).
      backgroundColor: NuvoColors.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _cameraLayer(),
          _scrim(),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                if (_toast != null) _toastBanner(),
                _pasteBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraLayer() {
    final cam = _camera;
    if (_state == _ScanState.scanning && cam != null && cam.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: cam.value.previewSize?.height ?? 1080,
          height: cam.value.previewSize?.width ?? 1920,
          child: CameraPreview(cam),
        ),
      );
    }
    return Container(color: NuvoColors.navy, child: Center(child: _statusCard()));
  }

  Widget _statusCard() {
    switch (_state) {
      case _ScanState.starting:
        return const NuvoLoadingIndicator(color: NuvoColors.white);
      case _ScanState.permissionDenied:
        return _MessageCard(
          icon: Icons.lock_outline_rounded,
          title: 'Camera access needed',
          body: 'Nuvo needs the camera to scan a code. Turn it on in Settings.',
          ctaLabel: 'Open Settings',
          onCta: () => launchUrl(Uri.parse('app-settings:')),
        );
      case _ScanState.noCamera:
        return const _MessageCard(
          icon: Icons.no_photography_rounded,
          title: 'No camera',
          body: 'This device has no camera. Paste a link instead.',
        );
      case _ScanState.error:
        return _MessageCard(
          icon: Icons.error_outline_rounded,
          title: "Camera didn't start",
          body: _errorText ?? 'Try again, or paste a link.',
          ctaLabel: 'Retry',
          onCta: _start,
        );
      case _ScanState.scanning:
        return const SizedBox.shrink();
    }
  }

  Widget _scrim() {
    if (_state != _ScanState.scanning) return const SizedBox.shrink();
    return Center(
      child: Container(
        width: 248,
        height: 248,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.close_rounded,
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/pass');
              }
            },
          ),
          const SizedBox(width: 12),
          Text('Scan a Nuvo code',
              style: AppTextStyles.titleMedium.copyWith(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _toastBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_toast!, style: AppTextStyles.bodySmall.copyWith(color: Colors.white)),
    );
  }

  Widget _pasteBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      color: Colors.black.withValues(alpha: 0.55),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _pasteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Or paste a Nuvo link',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (_) => _submitPasted(),
            ),
          ),
          const SizedBox(width: 8),
          NuvoPrimaryButton(label: 'Open', onPressed: _submitPasted),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.page,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: NuvoColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.textMuted),
              textAlign: TextAlign.center),
          if (ctaLabel != null) ...[
            const SizedBox(height: 16),
            NuvoPrimaryButton(label: ctaLabel!, expand: true, onPressed: onCta),
          ],
        ],
      ),
    );
  }
}
