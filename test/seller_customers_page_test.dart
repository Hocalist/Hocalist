import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/customers.dart';
import 'package:hocalist/features/seller/seller_customers_page.dart';

void main() {
  testWidgets('customer pages preserve drafts and retry intent across navigation', (tester) async {
    final writes = <(String, bool, String)>[];
    final customers = List.generate(11, (i) => SellerCustomer(
      buyerId: 'buyer-$i', displayName: 'Buyer $i', purchaseCount: 1,
      lastPurchaseAt: DateTime(2026, 10, 30), saved: false, note: ''));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SellerCustomersPage(
      load: () async => (insightsAvailable: false, items: customers),
      save: (id, saved, note) async {
        writes.add((id, saved, note));
        if (writes.length == 1) throw StateError('Unknown outcome');
      },
      history: (_) async => throw StateError('Not used'), onBack: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Buyer 10'), findsNothing);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Previous')).onPressed, isNull);
    final notes = find.widgetWithText(TextButton, 'Private notes').first;
    expect(tester.getTopLeft(notes).dy - tester.getBottomLeft(find.byType(Divider).first).dy, greaterThanOrEqualTo(10));
    await tester.tap(notes);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.scrollUntilVisible(find.text('Next').hitTestable(), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Buyer 10'), findsOneWidget);
    expect(find.text('Buyer 0'), findsNothing);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Next')).onPressed, isNull);
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Keep this draft');
    await tester.ensureVisible(find.byKey(const Key('customer-save-toggle')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer-save-toggle')).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next').hitTestable(), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    await tester.ensureVisible(find.text('Retry save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(writes, [('buyer-0', true, 'Keep this draft'), ('buyer-0', true, 'Keep this draft')]);
    expect(tester.takeException(), isNull);
  });
  final customer = SellerCustomer(buyerId: 'buyer-a', displayName: 'Test Buyer',
    purchaseCount: 2, lastPurchaseAt: DateTime(2026, 10, 30), saved: false, note: '');
  for (final (width, scale) in [for (final width in [320.0, 360.0, 390.0, 430.0]) for (final scale in [1.0, 1.15, 1.3, 1.6]) (width, scale)]) {
    testWidgets('current customer layout reflows at $width with text scale $scale', (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: Size(width, 740), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SellerCustomersPage(
          load: () async => (insightsAvailable: true, items: [customer]),
          save: (_, _, _) async {}, history: (_) async => const CustomerHistory(
            concludedRequests: 44, confirmedPurchases: 18, ongoingRequests: 4, completionPercent: 40.9),
          onBack: () {},
        )),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private notes'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View purchase history'));
    await tester.pumpAndSettle();
      await tester.tap(find.text('View purchase history'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('40.9%'), findsOneWidget);
    });
  }
  testWidgets('unknown save freezes exact intent and history labels factual rate', (tester) async {
    final writes = <(String, bool, String)>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SellerCustomersPage(
      load: () async => (insightsAvailable: true, items: [customer]),
      save: (id, saved, note) async {
        writes.add((id, saved, note));
        if (writes.length == 1) throw StateError('Unknown outcome');
      },
      history: (id) async => const CustomerHistory(concludedRequests: 2,
        confirmedPurchases: 1, ongoingRequests: 3, completionPercent: 50),
      onBack: () {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic private note');
    await tester.tap(find.byKey(const Key('customer-save-toggle')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(tester.widget<IconButton>(find.byKey(const Key('customer-save-toggle'))).onPressed, isNull);
    await tester.ensureVisible(find.text('Retry save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(writes, [('buyer-a', true, 'Synthetic private note'), ('buyer-a', true, 'Synthetic private note')]);
    await tester.ensureVisible(find.text('View purchase history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View purchase history'));
    await tester.pumpAndSettle();
    expect(find.text('Historical completion rate: 50.0%'), findsOneWidget);
    expect(find.textContaining('3 ongoing requests excluded'), findsOneWidget);
    await tester.ensureVisible(find.text('Close purchase history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close purchase history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Historical completion rate:'), findsNothing);
    expect(find.textContaining('3 ongoing requests excluded'), findsNothing);
    expect(find.text('Close purchase history'), findsNothing);
    expect(find.text('View purchase history'), findsOneWidget);
    await tester.tap(find.text('View purchase history'));
    await tester.pumpAndSettle();
    expect(find.text('Historical completion rate: 50.0%'), findsOneWidget);
    expect(find.text('Close purchase history'), findsOneWidget);
  });

  testWidgets('Pro customer tools do not offer Elite insights', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SellerCustomersPage(
      load: () async => (insightsAvailable: false, items: [customer]),
      save: (_, _, _) async {}, history: (_) async => throw StateError('Must not call'),
      onBack: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('View purchase history'), findsNothing);
    expect(find.text('Purchase history insights require Elite.'), findsOneWidget);
  });
}



