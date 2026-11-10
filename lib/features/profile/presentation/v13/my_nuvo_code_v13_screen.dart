import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/v13/v13.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../crew/application/crew_controller.dart';
import '../../../crew/data/crew_api.dart';
import '../../../races/ai/camera_image_converter.dart';
import '../../../races/data/race_models.dart';
import '../../../social/data/barcode_scanner_service.dart';
import '../../../social/data/invite_models.dart';
import '../../../social/domain/nuvo_destination.dart';
import '../../../social/social_providers.dart';

/// `/my-nuvo` — the v13 member code. Segmented My code / Scan; the initial
/// segment arrives from `?tab=scan`. My code shows the personal invite QR;
/// Scan embeds the live camera scanner (same pipeline as the old screen).
class MyNuvoCodeV13Screen extends ConsumerStatefulWidget {
  const MyNuvoCodeV13Screen({super.key, this.initialTab = 0});

  /// 0 = My code, 1 = Scan — `/my-nuvo?tab=scan` passes 1.
  final int initialTab;

  @override
  ConsumerState<MyNuvoCodeV13Screen> createState() =>
      _MyNuvoCodeV13ScreenState();
}

class _MyNuvoCodeV13ScreenState extends ConsumerState<MyNuvoCodeV13Screen> {
  late int _tab = widget.initialTab == 1 ? 1 : 0;
  MintedInvite? _invite;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  /// Last minted link, kept on device so the code still shows offline.
  String? _cachedUrl;

  Future<File> _codeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final uid = ref.read(authControllerProvider).user?.id ?? 'anon';
    return File('${dir.path}/nuvo_my_code_$uid.txt');
  }

  Future<void> _loadInvite() async {
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .mintMyCrewInvite();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _error = null;
      });
      try {
        await (await _codeFile()).writeAsString(invite.url);
      } catch (_) {}
    } catch (e) {
      // Offline: fall back to the last code minted on this device.
      try {
        final f = await _codeFile();
        if (await f.exists()) {
          final url = (await f.readAsString()).trim();
          if (url.isNotEmpty && mounted) {
            setState(() {
              _cachedUrl = url;
              _error = null;
            });
            return;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'My Nuvo'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: V13Segmented(
                segments: const [
                  V13Segment(label: 'My code', icon: Icons.qr_code_2_rounded),
                  V13Segment(label: 'Scan', icon: Icons.photo_camera_rounded),
                ],
                selectedIndex: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: _tab == 0 ? _myCode(user?.username) : const _ScanPane(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myCode(String? username) {
    if (_error != null) {
      return V13AsyncView<MintedInvite>.state(
        status: V13AsyncStatus.error,
        errorTitle: "Couldn't load your code",
        errorBody: 'Check your connection and try again.',
        onRetry: _loadInvite,
        builder: (_) => const SizedBox.shrink(),
      );
    }
    final url = _invite?.url ?? _cachedUrl;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapXl,
        V13.pagePad,
        V13.gapXxl * 2,
      ),
      children: [
        V13Card(
          padding: const EdgeInsets.all(V13.gapXl),
          child: Column(
            children: [
              if (url == null)
                const V13Skeleton(height: 240, radius: V13.radiusCard)
              else
                V13NuvoQr(data: url),
              const SizedBox(height: V13.gapLg),
              Text(
                username != null && username.isNotEmpty
                    ? '@$username'
                    : 'Your Nuvo code',
                style: V13.bodyStrong,
              ),
              Text('Friends scan this to race with you.', style: V13.caption),
            ],
          ),
        ),
        const SizedBox(height: V13.gapLg),
        V13Button.primary(
          label: 'Share your code',
          icon: Icons.ios_share_rounded,
          onPressed: url == null ? null : () => shareMyNuvoLink(context, url),
        ),
        const SizedBox(height: V13.gapMd),
        V13Button.secondary(
          label: 'Copy link',
          icon: Icons.link_rounded,
          onPressed: url == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    showV13Toast(context, 'Link copied.');
                  }
                },
        ),
      ],
    );
  }
}

/// Live QR scanner — same camera + barcode pipeline as the old `/scan`
/// screen, restyled for v13. Resolves a scanned Nuvo code to a person
/// (friend invite) or routes the destination like every other entry point.
class _ScanPane extends ConsumerStatefulWidget {
  const _ScanPane();

  @override
  ConsumerState<_ScanPane> createState() => _ScanPaneState();
}

enum _ScanStatus { starting, scanning, permissionDenied, noCamera, error }

class _ScanPaneState extends ConsumerState<_ScanPane>
    with WidgetsBindingObserver {
  CameraController? _camera;
  final _scanner = BarcodeScannerService();
  final _pasteController = TextEditingController();

  _ScanStatus _status = _ScanStatus.starting;
  bool _processing = false;
  bool _handled = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  /// Resolved person invite — the scanner pauses while the card shows.
  PersonInviteCard? _found;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pasteController.dispose();
    _camera?.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed &&
        _status == _ScanStatus.permissionDenied) {
      _start();
    }
  }

  Future<void> _start() async {
    setState(() => _status = _ScanStatus.starting);
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _status = _ScanStatus.noCamera);
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
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      _camera = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) return;
      setState(() => _status = _ScanStatus.scanning);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied =
          e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted';
      setState(() {
        _status = denied ? _ScanStatus.permissionDenied : _ScanStatus.error;
      });
    } catch (_) {
      if (mounted) setState(() => _status = _ScanStatus.error);
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _handled || _found != null) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame) < const Duration(milliseconds: 250)) {
      return;
    }
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
      // A single bad frame never kills the scan loop.
    } finally {
      _processing = false;
    }
  }

  Future<void> _consider(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    final dest = uri == null ? null : NuvoDestination.tryParse(uri);
    if (dest == null) {
      if (mounted) showV13Toast(context, "That isn't a Nuvo code.");
      return;
    }
    // Person invites resolve to a card here; every other destination routes
    // through the shared destination flow like the old scanner.
    if (dest is InviteDestination) {
      _handled = true;
      await _camera?.stopImageStream().catchError((_) {});
      try {
        final preview = await ref
            .read(inviteRepositoryProvider)
            .preview(dest.token);
        if (!mounted) return;
        final person = preview.person;
        if (preview.isAvailable && person != null) {
          setState(() {
            _found = person;
            _handled = false;
          });
          return;
        }
        final location = preview.destination?.location ?? dest.location;
        _push(location);
        return;
      } catch (_) {
        if (!mounted) return;
        _handled = false;
        await _camera?.startImageStream(_onFrame).catchError((_) {});
        showV13Toast(context, "Couldn't read that code. Try again.");
        return;
      }
    }
    _handled = true;
    await _camera?.stopImageStream().catchError((_) {});
    _push(dest.location);
  }

  void _push(String location) {
    if (!mounted) return;
    context.push(location);
    // Returning from the pushed screen resumes scanning.
    _handled = false;
    _camera?.startImageStream(_onFrame).catchError((_) {});
  }

  Future<void> _addFriend() async {
    final person = _found;
    if (person == null || _adding) return;
    setState(() => _adding = true);
    try {
      final outcome = await ref
          .read(crewControllerProvider.notifier)
          .add(
            PublicUser(
              id: person.userId,
              displayName: person.displayName,
              username: person.username,
              initials: _initials(person.displayName),
              profilePhotoUrl: person.profilePhotoUrl,
            ),
          );
      if (!mounted) return;
      showV13Confetti(context);
      showV13Toast(
        context,
        outcome == ConnectOutcome.active
            ? 'Added to your friends.'
            : 'Request sent.',
      );
      setState(() {
        _found = null;
        _adding = false;
      });
      await _camera?.startImageStream(_onFrame).catchError((_) {});
    } catch (_) {
      if (mounted) {
        setState(() => _adding = false);
        showV13Toast(context, "Couldn't add them. Try again.");
      }
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.elementAt(1)[0]}'.toUpperCase();
    }
    return name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();
  }

  void _submitPasted() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;
    _consider(text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapXl,
        V13.pagePad,
        V13.gapLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The viewfinder is a framed card inside the page — the camera never
          // bleeds under the header or the segmented control.
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(
                aspectRatio: keyboard ? 1.6 : 0.82,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(V13.radiusCardLg),
                    border: Border.all(color: V13.navy, width: V13.outline),
                    boxShadow: V13.shadow6,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      V13.radiusCardLg - V13.outline,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _cameraLayer(),
                        if (_status == _ScanStatus.scanning && _found == null)
                          const IgnorePointer(child: _Reticle()),
                        if (_found != null) _foundCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!keyboard && _status == _ScanStatus.scanning) ...[
            const SizedBox(height: V13.gapMd),
            Text(
              _found == null
                  ? 'Point your camera at a friend\u2019s Nuvo code.'
                  : 'Found them.',
              style: V13.caption,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: V13.gapLg),
          _pasteBar(),
        ],
      ),
    );
  }

  Widget _cameraLayer() {
    final cam = _camera;
    if (_status == _ScanStatus.scanning &&
        cam != null &&
        cam.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: cam.value.previewSize?.height ?? 1080,
          height: cam.value.previewSize?.width ?? 1920,
          child: CameraPreview(cam),
        ),
      );
    }
    // Non-camera states sit on a light card so the viewfinder frame reads
    // (navy-on-navy hid the outline and made the shadow look like a smear).
    return ColoredBox(
      color: _status == _ScanStatus.starting ? V13.navy : V13.card,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(V13.gapLg),
          child: _statusCard(),
        ),
      ),
    );
  }

  Widget _statusCard() {
    switch (_status) {
      case _ScanStatus.starting:
        return const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(color: V13.card, strokeWidth: 3),
        );
      case _ScanStatus.permissionDenied:
        return _scanMessage(
          icon: Icons.lock_outline_rounded,
          title: 'Camera access needed',
          body: 'Nuvo needs the camera to scan a code.',
          ctaLabel: 'Open Settings',
          onCta: () => launchUrl(Uri.parse('app-settings:')),
        );
      case _ScanStatus.noCamera:
        return _scanMessage(
          icon: Icons.no_photography_rounded,
          title: 'No camera',
          body: 'This device has no camera. Paste a Nuvo link below instead.',
        );
      case _ScanStatus.error:
        return _scanMessage(
          icon: Icons.error_outline_rounded,
          title: "Camera didn't start",
          body: 'Try again, or paste a link below.',
          ctaLabel: 'Retry',
          onCta: _start,
        );
      case _ScanStatus.scanning:
        return const SizedBox.shrink();
    }
  }

  Widget _scanMessage({
    required IconData icon,
    required String title,
    required String body,
    String? ctaLabel,
    VoidCallback? onCta,
  }) {
    return Padding(
      padding: const EdgeInsets.all(V13.gapMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          V13IconTile(icon: icon, color: V13.sky),
          const SizedBox(height: V13.gapMd),
          Text(title, style: V13.bodyStrong, textAlign: TextAlign.center),
          const SizedBox(height: V13.gapXs),
          Text(body, style: V13.body, textAlign: TextAlign.center),
          if (ctaLabel != null) ...[
            const SizedBox(height: V13.gapMd),
            V13Button.secondary(
              label: ctaLabel,
              size: V13ButtonSize.small,
              onPressed: onCta,
            ),
          ],
        ],
      ),
    );
  }

  Widget _foundCard() {
    final person = _found!;
    return ColoredBox(
      color: V13.navy.withValues(alpha: 0.55),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(V13.pagePad),
          child: V13Card(
            padding: const EdgeInsets.all(V13.gapXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                V13Face(
                  photoUrl: person.profilePhotoUrl,
                  size: 72,
                  name: person.displayName,
                ),
                const SizedBox(height: V13.gapMd),
                Text(person.displayName, style: V13.sectionHead),
                if (person.username != null && person.username!.isNotEmpty)
                  Text('@${person.username}', style: V13.caption),
                const SizedBox(height: V13.gapLg),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    V13Button.secondary(
                      label: 'Keep scanning',
                      size: V13ButtonSize.small,
                      onPressed: () async {
                        setState(() {
                          _found = null;
                        });
                        await _camera
                            ?.startImageStream(_onFrame)
                            .catchError((_) {});
                      },
                    ),
                    const SizedBox(width: V13.gapMd),
                    V13Button.primary(
                      label: 'Add friend',
                      size: V13ButtonSize.small,
                      loading: _adding,
                      onPressed: _adding ? null : _addFriend,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) showV13Toast(context, 'Nothing to paste.');
      return;
    }
    _pasteController.text = text;
    _submitPasted();
  }

  Widget _pasteBar() {
    return Row(
      children: [
        Expanded(
          child: V13TextInput(
            controller: _pasteController,
            hint: 'Or paste a Nuvo link',
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitPasted(),
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste_rounded, color: V13.navy),
              onPressed: _pasteFromClipboard,
            ),
          ),
        ),
        const SizedBox(width: V13.gapSm),
        V13Button.primary(
          label: 'Go',
          size: V13ButtonSize.medium,
          fullWidth: false,
          onPressed: _submitPasted,
        ),
      ],
    );
  }
}

/// Corner brackets that frame the scan area inside the viewfinder.
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: .62,
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _ReticlePainter()),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = V13.card
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final l = size.width * .2;
    const r = 18.0;
    final w = size.width, h = size.height;
    // Each corner is an L with a rounded elbow.
    for (final path in [
      Path()
        ..moveTo(0, l)
        ..lineTo(0, r)
        ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
        ..lineTo(l, 0),
      Path()
        ..moveTo(w - l, 0)
        ..lineTo(w - r, 0)
        ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
        ..lineTo(w, l),
      Path()
        ..moveTo(w, h - l)
        ..lineTo(w, h - r)
        ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
        ..lineTo(w - l, h),
      Path()
        ..moveTo(l, h)
        ..lineTo(r, h)
        ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
        ..lineTo(0, h - l),
    ]) {
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter oldDelegate) => false;
}

/// The one way Nuvo shares "add me" — My code's "Share your code" and
/// Profile's "Share profile" both call this, so the link and copy can't
/// drift. Opens the iOS share sheet (anchored to [context] for iPad); if the
/// sheet can't open, copies the link and says so.
Future<void> shareMyNuvoLink(BuildContext context, String url) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    await Share.share(
      'Add me on Nuvo — $url',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showV13Toast(context, 'Link copied.');
  }
}
