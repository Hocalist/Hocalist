import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/main.dart' show AppFrame;
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('full meetings empty state stays visible at $width/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: AppFrame(
                  childOwnsScroll: true,
                  header: const Text('Buyer mode'),
                  child: ApprovedBuyerMeetingsPage(
                    onBack: () {},
                    meetings: const [],
                    loading: false,
                    error: null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('No upcoming meetings yet').hitTestable(),
          findsOneWidget,
        );
      });
    }
  }
}
