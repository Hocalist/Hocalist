import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/features/discovery/buyer_public_profile_page.dart';

void main() {
  testWidgets('buyer consent withheld renders privacy without invented facts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerPublicProfilePage(
            onBack: () {},
            load: () async => const PublicBuyerProfile(available: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This profile is private'), findsOneWidget);
    expect(find.text('Confirmed purchases'), findsNothing);
    expect(find.text('Verified buyer'), findsNothing);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('consented buyer profile fits $width/$scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
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
                body: SingleChildScrollView(
                  child: BuyerPublicProfilePage(
                    onBack: () {},
                    load: () async => PublicBuyerProfile(
                      available: true,
                      displayName: 'Test buyer',
                      areaLabel: 'Chicago',
                      verifiedPurchaseCount: 3,
                      memberSince: DateTime.utc(2026),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Test buyer'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('buyer profile read failure has reachable retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerPublicProfilePage(
            onBack: () {},
            load: () async {
              if (++calls == 1) throw Exception('test');
              return const PublicBuyerProfile(available: false);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('This profile is private'), findsOneWidget);
  });
}
