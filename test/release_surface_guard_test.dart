import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tripwire: developer / diagnostic controls must never render in a normal
/// beta/release build. Diagnostics stay *collected* internally — this guards
/// the *UI surface* only.
///
/// Widget tests run in debug mode (where these surfaces are deliberately
/// visible), so this is a source-level check:
///  1. every dev-control label is a comment, near a release gate, or inside a
///     known diagnostic render/action method;
///  2. every call site of those methods is near a release gate — the
///     guarantee that keeps them off a tester's screen.
void main() {
  const forbiddenLabels = <String>[
    'Copy raw debug JSON',
    'Copy debug report',
    'Copy Motion V2 Log',
    'Copy failed-attempt fixture',
    'Save Diagnostic Session',
    'Share session',
    "'DEBUG'",
    "'MOTION V2'",
  ];

  const gateTokens = <String>[
    'kDebugMode',
    'kNuvoDiagnosticsEnabled',
    '_showDiagnostics',
    'kReleaseMode',
  ];

  /// The diagnostic render/action methods. A forbidden label inside one of
  /// these is fine; every *call* to one must be gated.
  const diagnosticMethods = <String>[
    '_debugPanel',
    '_motionV2DebugPanel',
    '_customDebugOverlay',
    '_copyDebugReport',
    '_copyRawDebugJson',
    '_copyMotionV2Log',
    '_copyMotionV2Debug',
    '_saveDiagnosticSession',
    '_copyFailedAttemptFixture',
    '_shareSession',
    '_copyRaceComposerDebugReport',
  ];
  final methodDecl = RegExp(r'^\s*(?:@override\s*)?[\w<>,?\s]+\s+(_\w+)\s*\(');

  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String? enclosingMethod(List<String> lines, int i) {
    for (var j = i; j >= 0; j--) {
      final m = methodDecl.firstMatch(lines[j]);
      if (m != null) return m.group(1);
    }
    return null;
  }

  bool gatedWithin(List<String> lines, int i, int window) {
    final from = (i - window).clamp(0, lines.length);
    return gateTokens
        .any(lines.sublist(from, i + 1).join('\n').contains);
  }

  test('1. no ungated developer label in lib/', () {
    final offenders = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (final label in forbiddenLabels) {
          if (!lines[i].contains(label)) continue;
          final ok = gatedWithin(lines, i, 20) ||
              diagnosticMethods.contains(enclosingMethod(lines, i));
          if (!ok) offenders.add('${file.path}:${i + 1}  →  $label');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'ungated dev label:\n${offenders.join('\n')}');
  });

  test('2. every diagnostic method call site is release-gated', () {
    final offenders = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Skip the declaration line itself, and any call made from *inside*
        // another diagnostic method (that method's own call site is gated).
        if (methodDecl.hasMatch(lines[i]) &&
            diagnosticMethods.contains(methodDecl.firstMatch(lines[i])!.group(1))) {
          continue;
        }
        if (diagnosticMethods.contains(enclosingMethod(lines, i))) continue;
        for (final name in diagnosticMethods) {
          // A reference that is a call / tear-off, not a definition.
          if (!RegExp('[^A-Za-z0-9_]$name *[,)(\n]').hasMatch('${lines[i]}\n')) {
            continue;
          }
          if (!gatedWithin(lines, i, 14)) {
            offenders.add('${file.path}:${i + 1}  →  calls $name ungated');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'ungated diagnostic call site:\n${offenders.join('\n')}');
  });

  test('3. NUVO_DIAGNOSTICS defaults off', () {
    expect(const bool.fromEnvironment('NUVO_DIAGNOSTICS'), isFalse);
  });
}
