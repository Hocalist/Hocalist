import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/features/seller/approved_seller_chats_page.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/approved_seller_meets_page.dart';
import 'package:hocalist/main.dart';

import 'test_fonts.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadHocalistTestFonts);
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets('Hocatrends search filters visible opportunities', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
    );

    await tester.tap(find.byKey(const Key('approved-hocatrends-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('approved-hocatrends-search-input')),
      'Used SUVs',
    );
    tester.testTextInput.hide();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('approved-trend-card-5')),
        matching: find.text('Used SUVs'),
      ),
      findsOneWidget,
    );
    expect(find.text('iPad Air'), findsNothing);
    expect(find.text('See Sellers'), findsOneWidget);
  });

  testWidgets('Hocatrends seller filters and sort change results', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedHocatrendsPickedSellersPage(onBack: () {}, onChatSeller: () {}),
      height: 1400,
    );

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Saves $160+'));
    await tester.tap(find.text('Show sellers'));
    await tester.pumpAndSettle();

    expect(find.text('Northside Tech'), findsOneWidget);
    expect(find.text('Gadget Hub'), findsOneWidget);
    expect(find.text('Prime Tech Solutions'), findsNothing);

    await tester.tap(find.text('Sort by: Best deal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top rated').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller Chats search filters conversations and clears', (
    tester,
  ) async {
    await _pump(tester, ApprovedSellerChatsPage(onOpenConversation: () {}));

    await tester.enterText(
      find.byKey(const Key('sellerChatsSearch')),
      'Alicia',
    );
    await tester.pump();
    expect(find.text('Alicia C.'), findsOneWidget);
    expect(find.text('Maya R.'), findsNothing);

    await tester.enterText(find.byKey(const Key('sellerChatsSearch')), '');
    await tester.pump();
    expect(find.text('Maya R.'), findsOneWidget);
  });

  testWidgets('Seller Leads and Meets top filters open current sheets', (
    tester,
  ) async {
    await _pump(tester, const ApprovedSellerLeadsPage());
    await tester.tap(find.byKey(const Key('sellerLeadsFilter')));
    await tester.pumpAndSettle();
    expect(find.text('Lead filters'), findsOneWidget);
    expect(find.text('Apply filters'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await _pump(tester, ApprovedSellerMeetsPage(onOpenChat: () {}));
    await tester.tap(find.byTooltip('Filter appointments'));
    await tester.pumpAndSettle();
    expect(find.text('Filter appointments'), findsWidgets);
    expect(find.text('Show appointments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request category and location selectors retain entered values', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedRequestFlowPage(
        accent: HocalistTheme.actionBlue,
        requestTitle: 'House cleaning',
        budget: '',
        initialKind: ApprovedRequestKind.service,
        onTitleChanged: (_) {},
        onBudgetChanged: (_) {},
        onBack: () {},
        onNotifications: () {},
        onSubmit: () {},
      ),
      height: 900,
    );
    await tester.ensureVisible(
      find.byKey(const Key('approved-request-category-select')),
    );
    await tester.tap(find.byKey(const Key('approved-request-category-select')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('approved-request-category-input')),
      'Home services',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use category'));
    await tester.tap(find.text('Use category'));
    await tester.pumpAndSettle();
    expect(find.text('Home services'), findsOneWidget);

    await _pump(
      tester,
      ApprovedLocationRequestStep(
        useHomeAddress: false,
        onUseHomeAddressChanged: (_) {},
        onBack: () {},
        onSubmit: () {},
      ),
      height: 1000,
    );
    await tester.tap(find.byKey(const Key('approved-request-address-state')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('approved-request-state-picker-input')),
      'New York',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use state'));
    await tester.tap(find.text('Use state'));
    await tester.pumpAndSettle();
    expect(find.text('New York'), findsOneWidget);
  });
}
