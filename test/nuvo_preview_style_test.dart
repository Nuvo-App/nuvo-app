import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/design/nuvo_preview_controller.dart';
import 'package:nuvo/core/design/nuvo_preview_style.dart';
import 'package:nuvo/core/widgets/preview_style_chooser.dart';

void main() {
  test('preview style starts unselected and can be changed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(nuvoPreviewStyleProvider), isNull);

    container
        .read(nuvoPreviewStyleProvider.notifier)
        .select(NuvoPreviewStyle.trackside);
    expect(
      container.read(nuvoPreviewStyleProvider),
      NuvoPreviewStyle.trackside,
    );

    container.read(nuvoPreviewStyleProvider.notifier).showChooser();
    expect(container.read(nuvoPreviewStyleProvider), isNull);
  });

  testWidgets('chooser exposes all three directions and returns selection', (
    tester,
  ) async {
    NuvoPreviewStyle? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [NuvoVisualTheme.startingLine]),
        home: PreviewStyleChooser(onSelected: (style) => selected = style),
      ),
    );

    expect(find.text('Starting Line'), findsOneWidget);
    expect(find.text('Trackside'), findsOneWidget);
    expect(find.text('Crew Momentum'), findsOneWidget);

    await tester.ensureVisible(find.text('Trackside'));
    await tester.tap(find.text('Trackside'));
    expect(selected, NuvoPreviewStyle.trackside);
  });
}
