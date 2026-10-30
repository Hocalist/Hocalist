import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/commercial/competing_offers_panel.dart';

void main() {
  testWidgets(
    'Elite prices need explicit consent; cancel preserves eligibility',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompetingOffersPanel(
              requestId: 'request',
              loadElite: () async => true,
              loadPrices: (id) async {
                calls++;
                return ['USD 45.00'];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View competing offers'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Keep refund eligibility'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('View competing offers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View prices and give up refund'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('USD 45.00'), findsOneWidget);
    },
  );
  testWidgets('Non-Elite and unavailable entitlements expose no action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompetingOffersPanel(
          requestId: 'r',
          loadElite: () async => false,
          loadPrices: (_) async => throw StateError('must not call'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('View competing offers'), findsNothing);
  });
  testWidgets('Failure does not display prices or pretend refund changed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetingOffersPanel(
            requestId: 'r',
            loadElite: () async => true,
            loadPrices: (_) async => throw StateError('denied'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View competing offers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View prices and give up refund'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unavailable for this deal'), findsOneWidget);
    expect(
      find.text('Refund eligibility has been removed for this request.'),
      findsNothing,
    );
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('consent fits width $width scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CompetingOffersPanel(
                    requestId: 'r',
                    loadElite: () async => true,
                    loadPrices: (_) async => [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View competing offers'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Keep refund eligibility'), findsOneWidget);
      });
    }
  }
}
