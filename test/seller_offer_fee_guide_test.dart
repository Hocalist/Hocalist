import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/seller/seller_offer_fee_guide.dart';

import '../tool/jons_dev.dart' as dev;

void main() {
  testWidgets('preview and Send offer use the selected seller plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const dev.JonsDevApp());
    await tester.pumpAndSettle();

    const reply =
        'The initial lead fee applies when the buyer replies to your offer.';
    const reserved = 'Your HocaCredits stay reserved while you negotiate.';
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text(reply), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Pro plan'), findsOneWidget);
    expect(find.text(reply), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Elite'));
    await tester.pumpAndSettle();
    expect(find.text('Elite plan'), findsOneWidget);
    expect(find.text(reserved), findsOneWidget);
    expect(find.text(reply), findsNothing);

    final help = find.byKey(const Key('sellerOfferFeeGuideHelp'));
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('viewing competing offers can affect'),
      findsOneWidget,
    );
    final helpNavigator = tester.state<NavigatorState>(find.byType(Navigator));
    helpNavigator.pop();
    await tester.pumpAndSettle();

    final offer = find.text('Open Send offer');
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('sellerSendOfferBottomSheet'));
    final guide = find.descendant(
      of: sheet,
      matching: find.byType(SellerOfferFeeGuide),
    );
    expect(tester.widget<SellerOfferFeeGuide>(guide).plan?.name, 'elite');
    expect(
      find.descendant(of: guide, matching: find.text(reserved)),
      findsOneWidget,
    );
  });
}
