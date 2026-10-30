import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/buyer_bottom_navigation.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'phase2/discovery/seller_home_discovery_ui_test.dart'
    show FakeReviewBackend;
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('review header and photo controls fit $width/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var notifications = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ApprovedBuyerReviewPage(
              onBack: () {},
              onFinish: () {},
              onNotifications: () => notifications++,
              imageUpload: (_, _) async => 'synthetic-id',
              navigation: ApprovedBuyerNavigation(
                onHome: () {},
                onHocatrends: () {},
                onOffers: () {},
                onChats: () {},
                onMore: () {},
              ),
              backend: FakeReviewBackend(),
              requestId: 'controlled-purchase',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BuyerTopLevelHeader), findsOneWidget);
        await tester.tap(find.byKey(BuyerTopLevelHeader.notificationsKey));
        await tester.pump();
        expect(notifications, 1);
        await tester.ensureVisible(find.text('Photos (optional)'));
        expect(find.text('Photos (optional)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
