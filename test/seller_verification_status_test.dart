import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';

void main() {
  testWidgets('verification actions open pop-ups without leaving the checklist', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ApprovedSellerVerificationPage(
      onBack:(){},onFinish:(){},identityStatus:'Not submitted',phoneStatus:'Not verified',emailStatus:'Verified',areaStatus:'No area saved',
      contactSection:const Text('Phone popup content'),emailSection:const Text('Email popup content'),
      areaSection:const Text('Area popup content'),reviewSection:const Text('Photo upload popup content'),
    )))));
    for(final pair in [('Phone','Phone popup content'),('Service area','Area popup content'),('Identity review','Photo upload popup content')]) {
      expect(find.text(pair.$2),findsNothing);
      await tester.ensureVisible(find.text(pair.$1));await tester.tap(find.text(pair.$1));await tester.pumpAndSettle();
      expect(find.text(pair.$2),findsOneWidget);
      Navigator.of(tester.element(find.text(pair.$2))).pop();await tester.pumpAndSettle();
      expect(find.byKey(const Key('approvedSellerVerificationPage')),findsOneWidget);
    }
  });
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
        expect(find.text('1 of 4 checks complete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
