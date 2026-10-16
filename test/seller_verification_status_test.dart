import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('real verification facts preserve fit at $width / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ApprovedSellerVerificationPage(
                  onBack: () {},
                  onFinish: () {},
                  identityStatus: 'Not submitted',
                  phoneStatus: 'Not verified',
                  areaStatus: 'Area saved',
                  reviewSection: const SizedBox(),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Not submitted'), findsOneWidget);
        expect(find.text('Not verified'), findsOneWidget);
        expect(find.text('Area saved'), findsOneWidget);
        expect(find.text('Ready to submit'), findsNothing);
        expect(find.text('Verification checklist'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
