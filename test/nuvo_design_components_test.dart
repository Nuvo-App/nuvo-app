import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/otp_input.dart';

void main() {
  testWidgets('bottom dock keeps every destination visible', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NuvoBottomNav(
            currentIndex: selected,
            onTap: (index) => selected = index,
          ),
        ),
      ),
    );

    expect(find.text('Arena'), findsOneWidget);
    expect(find.text('Compete'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    await tester.tap(find.text('Verify'));
    expect(selected, 2);
  });

  testWidgets('OTP input renders fixed clean boxes', (tester) async {
    final controllers = List.generate(6, (_) => TextEditingController());
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: OtpInput(controllers: controllers)),
        ),
      ),
    );

    expect(find.byType(TextField), findsNWidgets(6));
  });
}
