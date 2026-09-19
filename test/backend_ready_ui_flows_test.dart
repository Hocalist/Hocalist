import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/main.dart'
    show BuyerProfileEditPage, BuyerSupportStatusPage;
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

Future<void> _pumpScrollable(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBounded(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Buyer withdrawal completes its local review flow', (
    tester,
  ) async {
    var completed = 0;
    await _pumpScrollable(
      tester,
      ApprovedBuyerWithdrawalPage(onBack: () {}, onComplete: () => completed++),
    );

    await tester.tap(find.byKey(const Key('approved-withdrawal-destination')));
    await tester.pumpAndSettle();
    final buyerSheetTitle = tester.widget<Text>(
      find.byKey(const Key('approvedBuyerSheetTitle')),
    );
    expect(buyerSheetTitle.style?.fontSize, lessThanOrEqualTo(17));
    await tester.tap(find.byKey(const Key('approved-payout-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-withdrawal-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-withdrawal-confirm')));
    await tester.pumpAndSettle();

    expect(completed, 1);
    expect(
      find.byKey(const ValueKey('approved-withdrawal-success-page')),
      findsOneWidget,
    );
  });

  testWidgets('current Buyer notification destination keeps working filters', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}, title: 'Notifications'),
    );
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.text('Rewards'));
    await tester.pumpAndSettle();
    expect(find.text('Tech World NY confirmed your purchase'), findsOneWidget);
  });

  testWidgets('Buyer notification icons match the compact Seller scale', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}, title: 'Notifications'),
    );
    final firstRow = find.byKey(
      const ValueKey('approved-activity-2 minutes ago'),
    );
    final icon = find.descendant(of: firstRow, matching: find.byType(Image));
    expect(tester.getSize(icon.first), const Size(36, 36));
  });

  testWidgets('Buyer profile and rewards expose the expanded information', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      BuyerProfileEditPage(
        name: 'Maya Chen',
        onNameChanged: (_) {},
        onDone: () {},
      ),
    );
    expect(find.text('PHONE NUMBER'), findsOneWidget);
    expect(find.text('HOME AREA'), findsOneWidget);
    expect(find.text('PREFERRED MEETUP TYPE'), findsOneWidget);
    expect(find.text('PROFILE NOTE'), findsOneWidget);

    var payoutOpened = 0;
    await _pumpScrollable(
      tester,
      ApprovedBuyerRewardsDetailPage(
        onBack: () {},
        onDealHistory: () {},
        onWithdraw: () => payoutOpened++,
      ),
    );
    expect(find.text('Payout destination'), findsOneWidget);
    expect(find.text('Payout history'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('approved-rewards-payout-destination')),
    );
    await tester.tap(
      find.byKey(const Key('approved-rewards-payout-destination')),
    );
    expect(payoutOpened, 1);
  });

  testWidgets('chat attachment picker adds and removes a pending file', (
    tester,
  ) async {
    await _pumpBounded(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
      ),
    );
    await tester.drag(
      find.byKey(const Key('approved-chat-scroll')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-chat-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approved-pending-attachment')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('approved-remove-pending-attachment')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approved-pending-attachment')), findsNothing);
  });

  testWidgets(
    'public profiles and original request use upgraded destinations',
    (tester) async {
      await _pumpScrollable(
        tester,
        ApprovedSellerPublicProfilePage(onBack: () {}, onSelect: () {}),
      );
      expect(find.text('Seller profile'), findsOneWidget);
      expect(find.text('Select seller and open chat'), findsOneWidget);

      await _pumpScrollable(
        tester,
        ApprovedBuyerPublicProfilePage(onBack: () {}),
      );
      expect(find.text('Buyer profile'), findsOneWidget);
      expect(find.text('Maya Chen'), findsOneWidget);

      await _pumpScrollable(
        tester,
        ApprovedSellerOriginalRequestPage(onBack: () {}, onReturnToChat: () {}),
      );
      expect(find.text('Original request'), findsOneWidget);
      expect(find.text(r'$350–$480'), findsOneWidget);
    },
  );

  testWidgets('Buyer headers, actions, and fields use upgraded foundations', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      ApprovedSellerPublicProfilePage(onBack: () {}, onSelect: () {}),
    );
    final profileAction = find.byKey(
      const Key('approved-public-profile-select-seller'),
    );
    expect(tester.widget(profileAction), isA<BuyerPrimaryButton>());
    expect(tester.getSize(profileAction).height, lessThanOrEqualTo(50));
    expect(
      tester.widget<Text>(find.text('Seller profile')).style?.fontSize,
      closeTo(16, .01),
    );

    await _pumpScrollable(
      tester,
      ApprovedBuyerWithdrawalPage(onBack: () {}, onComplete: () {}),
    );
    final amountField = tester.widget<TextField>(
      find.byKey(const Key('approved-withdrawal-amount')),
    );
    expect(amountField.decoration?.labelText, isNull);
    expect(amountField.decoration?.filled, isTrue);
    expect(find.text('WITHDRAWAL AMOUNT'), findsOneWidget);

    await _pumpScrollable(
      tester,
      BuyerSupportStatusPage(
        accent: BuyerUiTokens.action,
        actionLabel: 'Back to Help & Support',
        onAction: () {},
      ),
    );
    expect(find.byType(BuyerPrimaryButton), findsOneWidget);
    expect(find.text('Back to Help & Support'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller primary action baseline stays at approved geometry', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      SellerPrimaryButton(label: 'Seller action', onPressed: () {}),
    );
    expect(tester.getSize(find.byType(SellerPrimaryButton)).height, 44);
    expect(tester.widget<Text>(find.text('Seller action')).style?.fontSize, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller can add and select a local payment-method preview', (
    tester,
  ) async {
    await _pumpScrollable(
      tester,
      ApprovedSellerPaymentMethodPage(onBack: () {}, onDone: () {}),
    );
    await tester.ensureVisible(find.byKey(const Key('sellerAddPaymentMethod')));
    await tester.tap(find.byKey(const Key('sellerAddPaymentMethod')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerAddPaymentMethodSheet')),
      findsOneWidget,
    );
    final paymentSheetTitle = tester.widget<Text>(
      find.byKey(const Key('sellerActionSheetTitle')),
    );
    expect(paymentSheetTitle.style?.fontSize, lessThanOrEqualTo(17));
    await tester.tap(find.byKey(const Key('sellerSavePaymentMethod')));
    await tester.pumpAndSettle();
    expect(find.text('Mastercard ending in 4444'), findsOneWidget);
    expect(find.text('Selected for Seller billing'), findsOneWidget);
  });

  testWidgets('Seller lead search changes the visible result set', (
    tester,
  ) async {
    await _pumpBounded(tester, const ApprovedSellerLeadsPage());
    await tester.enterText(
      find.byKey(const Key('sellerLeadsSearch')),
      'Alicia',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Alicia C.'), findsOneWidget);
    expect(find.textContaining('James M.'), findsNothing);
  });

  testWidgets('Seller add-product-images button fits a 320px offer sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 693);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SafeArea(child: ApprovedSellerLeadsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('sellerOfferAddImages'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller Help and Safety use upgraded responsive destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 693);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ApprovedSellerHelpSupportPage(
                onBack: () {},
                onSafety: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('approvedSellerHelpSupportPage')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('How targeting credits work'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerHelpAnswerSheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final support = find.text('Ask for help');
    await tester.ensureVisible(support);
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerSupportFormSheet')), findsOneWidget);
    final supportTitle = tester.widget<Text>(
      find.byKey(const Key('sellerActionSheetTitle')),
    );
    expect(supportTitle.style?.fontSize, inInclusiveRange(12, 16));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('sellerSupportTopic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credits or billing').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('sellerSupportSave')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final safetyReport = find.text('Report a safety concern');
    await tester.ensureVisible(safetyReport);
    await tester.tap(safetyReport);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('sellerActionSheetTitle'))).data,
      'Report a safety concern',
    );
    expect(find.text('Save safety report'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('sellerSupportSave'))).height,
      inInclusiveRange(36, 44),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('sellerSupportSave')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ApprovedSellerSafetyGuidePage(
                onBack: () {},
                onHelp: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approvedSellerSafetyGuidePage')),
      findsOneWidget,
    );
    expect(find.text('Use the buyer PIN only after the deal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller notification bell destination is an activity inbox', (
    tester,
  ) async {
    var preferencesOpened = 0;
    await _pumpScrollable(
      tester,
      ApprovedSellerNotificationsPage(
        onBack: () {},
        onPreferences: () => preferencesOpened++,
      ),
    );

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('New buyer request nearby'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('sellerNotificationFilters')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sellerNotificationFilter-billing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Targeting credit restored'), findsOneWidget);
    expect(find.text('New buyer request nearby'), findsNothing);
    await tester.tap(find.text('Targeting credit restored'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sellerNotificationDetailsSheet')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Seller billing exposes balance history and transaction details',
    (tester) async {
      await _pumpScrollable(
        tester,
        ApprovedSellerBillingPage(onBack: () {}, onPayment: () {}),
      );

      expect(find.byKey(const Key('sellerCreditBalanceCard')), findsOneWidget);
      expect(find.text(r'$36.25'), findsOneWidget);
      expect(find.text('BILLING HISTORY'), findsOneWidget);
      final activity = find.byKey(
        const ValueKey('sellerCreditActivity-TGT-250826-1042'),
      );
      await tester.ensureVisible(activity);
      await tester.tap(activity);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sellerTransactionDetailsSheet')),
        findsOneWidget,
      );
      expect(find.text('TGT-250826-1042'), findsOneWidget);
    },
  );
}
