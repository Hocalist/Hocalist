import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/profiles/public_profile_header.dart';
import 'package:hocalist/features/discovery/buyer_public_profile_page.dart';
import 'package:hocalist/domain/phase2/discovery.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets('public banner fits $width dark=$dark with large names and text', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: MediaQuery(data: MediaQueryData(size: Size(width, 1000), textScaler: TextScaler.linear(1.6)),
            child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16),
              child: PublicProfileHeader(name: 'A long public profile name that wraps', role: 'Buyer',
                subtitle: 'Johnson City', badges: const ['Email verified'],
                stats: const PublicProfileStats(values: {'Confirmed purchases': '12', 'Verification': 'Email & phone verified'})),
            ))))));
        await tester.pumpAndSettle();
        expect(find.text('AL'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('buyer uses shared banner only when public profile is available', (tester) async {
    Widget page(bool available) => MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: BuyerPublicProfilePage(onBack: () {},
        load: () async => PublicBuyerProfile(available: available, displayName: 'Test Buyer')))));
    await tester.pumpWidget(page(true)); await tester.pumpAndSettle();
    expect(find.byType(PublicProfileHeader), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page(false)); await tester.pumpAndSettle();
    expect(find.byType(PublicProfileHeader), findsNothing);
    expect(find.text('Test Buyer'), findsNothing);
  });
}
