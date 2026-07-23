import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nuvo_preview_style.dart';

final nuvoPreviewStyleProvider =
    StateNotifierProvider<NuvoPreviewController, NuvoPreviewStyle?>(
      (ref) => NuvoPreviewController(),
    );

final activeNuvoPreviewStyleProvider = Provider<NuvoPreviewStyle>(
  (ref) => ref.watch(nuvoPreviewStyleProvider) ?? NuvoPreviewStyle.startingLine,
);

class NuvoPreviewController extends StateNotifier<NuvoPreviewStyle?> {
  NuvoPreviewController() : super(null);

  void select(NuvoPreviewStyle style) => state = style;

  void showChooser() => state = null;
}
