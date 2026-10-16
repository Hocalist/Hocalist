import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/seller_payment_panel.dart';

void main() {
  test(
    'localhost app testing uses the same hosted billing origin as checkout returns',
    () {
      expect(sellerBillingWebsite(), Uri.parse('https://hocalist.com/billing'));
    },
  );
  testWidgets(
    'credit checkout opens billing without granting credits locally',
    (tester) async {
      Uri? destination;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerPaymentPanel(
              creditPurchase: true,
              open: (uri) async {
                destination = uri;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open credit checkout'));
      await tester.pumpAndSettle();
      expect(destination, sellerBillingWebsite());
      expect(find.textContaining('only after Stripe confirms'), findsOneWidget);
      expect(find.text('Manage payment method'), findsNothing);
    },
  );
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('payment controls fit $width / $scale', (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 850),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SellerPaymentPanel(open: (_) async => false),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Manage payment method'));
        await tester.pumpAndSettle();
        expect(find.text('Could not open billing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'opens only the billing website and prevents duplicate launches',
    (tester) async {
      final pending = Completer<bool>();
      var calls = 0;
      Uri? destination;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerPaymentPanel(
              open: (uri) {
                calls++;
                destination = uri;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manage payment method'));
      await tester.pump();
      expect(find.text('Opening billing…'), findsOneWidget);
      expect(calls, 1);
      expect(destination, Uri.parse('https://hocalist.com/billing'));
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Could not open billing'), findsOneWidget);
      expect(find.text('Manage payment method'), findsOneWidget);
    },
  );
  testWidgets('provider failure stays safe and retryable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerPaymentPanel(
            open: (_) async => throw StateError('secret detail'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage payment method'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open billing'), findsOneWidget);
    expect(find.textContaining('secret detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
