import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/approved_seller_meets_page.dart';
import 'package:hocalist/features/seller/approved_seller_chats_page.dart';
import 'package:hocalist/features/seller/approved_seller_more_page.dart';
import 'package:hocalist/features/seller/approved_seller_tutorial_page.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'package:hocalist/features/seller/seller_bottom_navigation.dart';
import 'package:hocalist/main.dart';

import 'test_fonts.dart';

class _SellerAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('assets/approved_seller/')) {
      return rootBundle.load(key);
    }
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadHocalistTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    required double width,
    double height = 932,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _SellerAssetBundle(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Nunito',
            scaffoldBackgroundColor: Colors.white,
          ),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, height),
                textScaler: TextScaler.linear(textScale),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ApprovedSellerHomePage home({VoidCallback? onLeads}) {
    return ApprovedSellerHomePage(
      onLeads: onLeads ?? () {},
      onBrowseRequests: () {},
    );
  }

  SellerNavigationCallbacks navigation({
    VoidCallback? onHome,
    VoidCallback? onLeads,
    VoidCallback? onMeets,
    VoidCallback? onChats,
    VoidCallback? onMore,
  }) => SellerNavigationCallbacks(
    onHome: onHome ?? () {},
    onLeads: onLeads ?? () {},
    onMeets: onMeets ?? () {},
    onChats: onChats ?? () {},
    onMore: onMore ?? () {},
  );

  Widget shell(
    Widget child, {
    SellerNavDestination selected = SellerNavDestination.home,
    SellerNavigationCallbacks? callbacks,
  }) => SellerAppShell(
    selected: selected,
    navigation: callbacks ?? navigation(),
    onNotifications: () {},
    child: child,
  );

  ApprovedSellerMorePage more() => ApprovedSellerMorePage(
    sellerName: 'Northside Tech',
    onProfile: () {},
    onEditProfile: () {},
    onSettings: () {},
    onNotifications: () {},
    onAccessibility: () {},
    onSafety: () {},
    onHelp: () {},
    onLogout: () {},
  );

  Widget nestedPage(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 56),
    child: child,
  );

  testWidgets('Seller Tutorial keeps the welcome and video fixed', (
    tester,
  ) async {
    for (final width in const [320.0, 430.0]) {
      await pumpSurface(
        tester,
        ApprovedSellerTutorialPage(onContinue: () {}, onClose: () {}),
        width: width,
        height: 720,
      );

      expect(find.text('Welcome, Jonathan'), findsOneWidget);
      expect(find.text('As a seller, you will:'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Seller tutorial video preview'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('More Seller benefits below'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const Key('sellerTutorialScrollCueOpacity')),
            )
            .opacity,
        1,
      );
      expect(find.bySemanticsLabel('Tutorial page 1 of 3'), findsNothing);

      final welcomeBefore = tester.getTopLeft(find.text('Welcome, Jonathan'));
      final videoBefore = tester.getTopLeft(
        find.bySemanticsLabel('Seller tutorial video preview'),
      );
      await tester.drag(
        find.byKey(const Key('sellerTutorialScroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Welcome, Jonathan')), welcomeBefore);
      expect(
        tester.getTopLeft(
          find.bySemanticsLabel('Seller tutorial video preview'),
        ),
        videoBefore,
      );
      expect(tester.takeException(), isNull, reason: 'at ${width}px wide');
    }
  });

  testWidgets(
    'Seller Tutorial scrolls the full surface at accessibility text sizes',
    (tester) async {
      await pumpSurface(
        tester,
        ApprovedSellerTutorialPage(onContinue: () {}, onClose: () {}),
        width: 320,
        height: 720,
        textScale: 1.6,
      );

      final scroll = find.byKey(const Key('sellerTutorialScroll'));
      final welcome = find.text('Welcome, Jonathan');
      final welcomeBefore = tester.getTopLeft(welcome).dy;
      await tester.drag(scroll, const Offset(0, -420));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(welcome).dy, lessThan(welcomeBefore - 100));
      await tester.scrollUntilVisible(
        find.byKey(const Key('sellerTutorialContinue')),
        320,
        scrollable: find.descendant(
          of: scroll,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const Key('sellerTutorialContinue')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Seller Tutorial Continue callback works', (tester) async {
    var continued = false;
    await pumpSurface(
      tester,
      ApprovedSellerTutorialPage(
        onContinue: () => continued = true,
        onClose: () {},
      ),
      width: 390,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerTutorialContinue')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('sellerTutorialScroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('sellerTutorialScrollCueOpacity')),
          )
          .opacity,
      0,
    );
    await tester.tap(find.byKey(const Key('sellerTutorialContinue')));
    await tester.pump();

    expect(continued, isTrue);
  });

  testWidgets('Seller choice drives account, tutorial, and Seller Home routes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _SellerAssetBundle(),
        child: const HocalistPrototype(),
      ),
    );
    await tester.pumpAndSettle();

    final sellerChoice = find.bySemanticsLabel(
      'I am selling. Target real customers and beat the competition. Browse requests.',
    );
    await tester.ensureVisible(sellerChoice);
    await tester.tap(sellerChoice);
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Store or seller name'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('approved-account-primary-action')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('approved-account-primary-action')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Jonathan'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerTutorialContinue')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerTutorialScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerTutorialContinue')));
    await tester.pumpAndSettle();

    expect(find.text('Seller mode'), findsOneWidget);
    expect(find.byKey(const Key('sellerNavHome')), findsOneWidget);
    expect(find.text('Find more buyers'), findsOneWidget);
  });

  testWidgets('Seller Chats opens the established conversation inside shell', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'hocalist.hasSession': true,
      'hocalist.role': 'seller',
      'hocalist.page': 'sellerChat',
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _SellerAssetBundle(),
        child: HocalistPrototype(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maya R.'), findsOneWidget);
    await tester.tap(find.text('Maya R.'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerConversationCurrent')), findsOneWidget);
    expect(find.byKey(const Key('approved-chat-scroll')), findsOneWidget);
    expect(find.byKey(const Key('sellerNavChats')), findsOneWidget);
    expect(find.byKey(const Key('active-deal-ipad')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller shell uses the approved five-tab navigation', (
    tester,
  ) async {
    await pumpSurface(tester, shell(home()), width: 430);

    for (final label in ['Home', 'Leads', 'Meets', 'Chats', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final oldLabel in ['Offers', 'Messages', 'Customers', 'Account']) {
      expect(find.text(oldLabel), findsNothing);
    }
    expect(find.text('Seller mode'), findsOneWidget);
    expect(find.text('Find more buyers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller Home Leads navigation callback works', (tester) async {
    var openedLeads = false;
    await pumpSurface(
      tester,
      shell(home(), callbacks: navigation(onLeads: () => openedLeads = true)),
      width: 390,
    );

    await tester.tap(find.byKey(const Key('sellerNavLeads')));
    await tester.pump();
    expect(openedLeads, isTrue);
  });

  testWidgets(
    'Leads prepare offer opens and cancels the approved bottom sheet',
    (tester) async {
      await pumpSurface(
        tester,
        shell(
          const ApprovedSellerLeadsPage(),
          selected: SellerNavDestination.leads,
        ),
        width: 390,
        height: 1000,
      );

      expect(find.text('Find Customers'), findsOneWidget);
      final verifiedFact = find.byKey(const Key('sellerVerifiedFactAC'));
      final verifiedIcon = find
          .descendant(of: verifiedFact, matching: find.byType(Icon))
          .first;
      final verifiedText = find.descendant(
        of: verifiedFact,
        matching: find.text('8 verified'),
      );
      expect(
        tester.getCenter(verifiedIcon).dx,
        lessThan(tester.getCenter(verifiedText).dx),
      );
      final aliciaCard = find.byKey(const Key('sellerLeadCardAC'));
      final prepareText = find.descendant(
        of: aliciaCard,
        matching: find.text('Prepare offer'),
      );
      expect(
        tester.getCenter(find.byKey(const Key('sellerPrepareOfferIconAC'))).dx,
        lessThan(tester.getCenter(prepareText).dx),
      );
      await tester.tap(find.text('Prepare offer').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sellerSendOfferBottomSheet')),
        findsOneWidget,
      );
      expect(find.text('Send your offer'), findsOneWidget);
      expect(find.text('Your Pro Plan'), findsOneWidget);
      expect(find.text(r'Initial bid $1.90'), findsOneWidget);
      expect(find.text(r'Winning Bid $4.75'), findsOneWidget);
      expect(find.text('Buyer is not open to higher offers.'), findsOneWidget);
      expect(find.text('Send your offer to the buyer.'), findsOneWidget);
      expect(
        find.byKey(const Key('sellerOfferCurrencyPrefix')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('sellerOfferCurrencyPrefix')))
            .width,
        lessThanOrEqualTo(50),
      );
      final priceField = tester.widget<TextField>(
        find.byKey(const Key('sellerOfferPrice')),
      );
      expect(priceField.controller?.text, '550');
      expect(
        find.byKey(const Key('sellerOfferMessageCounter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sellerOfferSpecificLocation')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sellerSendOfferClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsNothing);
      expect(find.text('Find Customers'), findsOneWidget);
    },
  );

  testWidgets('Send Offer submission returns to the same Leads context', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        const ApprovedSellerLeadsPage(),
        selected: SellerNavDestination.leads,
      ),
      width: 390,
      height: 1000,
    );

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerSendOfferSubmit')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerSendOfferScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsNothing);
    expect(find.text('Find Customers'), findsOneWidget);
    expect(find.byKey(const Key('sellerOfferSubmittedNotice')), findsOneWidget);
  });

  testWidgets('Send Offer reuses the Seller calendar and time-chip selector', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        const ApprovedSellerLeadsPage(),
        selected: SellerNavDestination.leads,
      ),
      width: 390,
      height: 1000,
    );

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    final offerScroll = find
        .descendant(
          of: find.byKey(const Key('sellerSendOfferScroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerOfferDate')),
      260,
      scrollable: offerScroll,
    );
    final dateTop = tester.getTopLeft(find.byKey(const Key('sellerOfferDate')));
    final timeTop = tester.getTopLeft(find.byKey(const Key('sellerOfferTime')));
    expect(dateTop.dy, closeTo(timeTop.dy, .5));
    await tester.tap(find.byKey(const Key('sellerOfferDate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerOfferScheduleDialog')), findsOneWidget);
    expect(find.text('1. Select a date'), findsOneWidget);
    expect(find.text('2. Select arrival time'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerOfferScheduleDay23')));
    final scheduleScroll = find
        .descendant(
          of: find.byKey(const Key('sellerOfferScheduleDialog')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerOfferSchedule2:00 PM')),
      180,
      scrollable: scheduleScroll,
    );
    await tester.tap(find.byKey(const Key('sellerOfferSchedule2:00 PM')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerOfferScheduleConfirm')),
      180,
      scrollable: scheduleScroll,
    );
    await tester.tap(find.byKey(const Key('sellerOfferScheduleConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Fri, May 23, 2025'), findsOneWidget);
    expect(find.text('2:00 PM'), findsOneWidget);
    final message = tester.widget<TextField>(
      find.byKey(const Key('sellerOfferMessage')),
    );
    expect(message.style?.fontSize, lessThanOrEqualTo(14));
    await tester.enterText(
      find.byKey(const Key('sellerOfferMessage')),
      'Hello',
    );
    await tester.pump();
    expect(find.text('5/250'), findsOneWidget);
    final messageRect = tester.getRect(
      find.byKey(const Key('sellerOfferMessage')),
    );
    final counterRect = tester.getRect(
      find.byKey(const Key('sellerOfferMessageCounter')),
    );
    expect(counterRect.right, lessThan(messageRect.right));
    expect(counterRect.bottom, lessThan(messageRect.bottom));
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerSendOfferSubmit')),
      160,
      scrollable: offerScroll,
    );
    await tester.pumpAndSettle();
    final visibleMessageRect = tester.getRect(
      find.byKey(const Key('sellerOfferMessage')),
    );
    final submitRect = tester.getRect(
      find.byKey(const Key('sellerSendOfferSubmit')),
    );
    expect(submitRect.top - visibleMessageRect.bottom, greaterThanOrEqualTo(8));
  });

  testWidgets(
    'specific location launches the future Places seam and keeps selection',
    (tester) async {
      var pickerCalled = false;
      await pumpSurface(
        tester,
        shell(
          ApprovedSellerLeadsPage(
            onChooseSpecificLocation: (context) async {
              pickerCalled = true;
              return const SellerOfferPlace(
                name: 'Selected public meetup',
                address: 'Returned by the place picker',
                placeId: 'place-test-123',
              );
            },
          ),
          selected: SellerNavDestination.leads,
        ),
        width: 390,
        height: 1000,
      );

      await tester.tap(find.text('Prepare offer').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('sellerOfferSpecificLocation')),
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('sellerSendOfferScroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('sellerOfferSpecificLocation')));
      await tester.pumpAndSettle();

      expect(pickerCalled, isTrue);
      expect(find.text('Selected public meetup'), findsOneWidget);
    },
  );

  testWidgets('specific location provides an upgraded local selection state', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        const ApprovedSellerLeadsPage(),
        selected: SellerNavDestination.leads,
      ),
      width: 390,
      height: 1000,
    );

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerOfferSpecificLocation')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerSendOfferScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerOfferSpecificLocation')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sellerPlacesConnectionDialog')),
      findsOneWidget,
    );
    expect(
      find.text(
        'These review locations are stored only in this prototype. Live place search connects with the location provider later.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cross County Mall'));
    await tester.pumpAndSettle();
    expect(find.text('Cross County Mall'), findsOneWidget);
  });

  testWidgets('Send Offer validates a missing price before submission', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        const ApprovedSellerLeadsPage(),
        selected: SellerNavDestination.leads,
      ),
      width: 390,
      height: 1000,
    );

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sellerOfferPrice')), '');
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerSendOfferSubmit')),
      320,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerSendOfferScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pump();

    expect(find.text('Enter a valid offer price.'), findsOneWidget);
    expect(find.byKey(const Key('sellerSendOfferBottomSheet')), findsOneWidget);
  });

  testWidgets('Prepare Offer reflows at 360 width and 1.6x text', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        const ApprovedSellerLeadsPage(),
        selected: SellerNavDestination.leads,
      ),
      width: 360,
      height: 900,
      textScale: 1.6,
    );

    await tester.drag(
      find.byKey(const Key('sellerLeadsScroll')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerSendOfferCancel')),
      360,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerSendOfferScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.byKey(const Key('sellerSendOfferCancel')), findsOneWidget);
    final sheetCenter = tester
        .getCenter(find.byKey(const Key('sellerSendOfferBottomSheet')))
        .dx;
    final headingCenter = tester
        .getCenter(find.byKey(const Key('sellerSendOfferHeading')))
        .dx;
    expect(headingCenter, closeTo(sheetCenter, 1));
    final submitBottom = tester
        .getBottomLeft(find.byKey(const Key('sellerSendOfferSubmit')))
        .dy;
    final cancelTop = tester
        .getTopLeft(find.byKey(const Key('sellerSendOfferCancel')))
        .dy;
    expect(cancelTop - submitBottom, greaterThanOrEqualTo(10));
    final compactBidText = tester.widget<Text>(find.text(r'Initial bid $1.90'));
    final compactHeading = tester.widget<Text>(find.text('Send your offer'));
    expect(
      compactBidText.style!.fontSize,
      lessThan(compactHeading.style!.fontSize!),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Meets, Chats, and More retain the Seller shell mapping', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(onOpenChat: () {}),
        selected: SellerNavDestination.meets,
      ),
      width: 390,
    );
    expect(find.byKey(const Key('sellerMeetsScroll')), findsOneWidget);
    expect(find.byKey(const Key('sellerNavMeets')), findsOneWidget);

    await pumpSurface(
      tester,
      shell(
        ApprovedSellerChatsPage(onOpenConversation: () {}),
        selected: SellerNavDestination.chats,
      ),
      width: 390,
    );
    expect(find.text('Chats'), findsWidgets);
    expect(find.byKey(const Key('sellerNavChats')), findsOneWidget);
    expect(find.text('Messages'), findsNothing);

    await pumpSurface(
      tester,
      shell(more(), selected: SellerNavDestination.more),
      width: 390,
    );
    expect(find.text('Northside Tech'), findsOneWidget);
    expect(find.text('northside.tech@example.com'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Account settings'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    expect(find.byKey(const Key('sellerNavMore')), findsOneWidget);
  });

  testWidgets('Meets product row reveals location and appointment actions', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(onOpenChat: () {}),
        selected: SellerNavDestination.meets,
      ),
      width: 390,
      height: 1000,
    );

    expect(find.text('Cross County Mall'), findsNothing);
    expect(find.text('Enter PIN'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerMeetProductJM')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerMeetsScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerMeetProductJM')));
    await tester.pump();

    expect(find.text('Cross County Mall'), findsOneWidget);
    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
  });

  testWidgets('Meets disclosure and status filters work at narrow width', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(onOpenChat: () {}, dealCompleted: true),
        selected: SellerNavDestination.meets,
      ),
      width: 320,
      height: 844,
    );

    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('Deal details'), findsNothing);
    expect(find.text('Meeting location'), findsNothing);
    expect(find.text('Alicia C.'), findsOneWidget);
    expect(find.text('Robert W.'), findsOneWidget);
    expect(find.text('James M.'), findsNothing);

    await tester.tap(find.byKey(const Key('sellerMeetFilterToday')));
    await tester.pumpAndSettle();
    expect(find.text('James M.'), findsOneWidget);
    expect(find.text('Alicia C.'), findsOneWidget);
    expect(find.text('Robert W.'), findsNothing);

    await tester.tap(find.byKey(const Key('sellerMeetFilterCompleted')));
    await tester.pumpAndSettle();
    expect(find.text('James M.'), findsOneWidget);
    expect(find.text('Alicia C.'), findsNothing);

    await tester.tap(find.byKey(const Key('sellerMeetFilterCanceled')));
    await tester.pumpAndSettle();
    expect(find.text('No canceled appointments'), findsOneWidget);
    expect(find.byKey(const Key('sellerMeetEmptycanceled')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sellerMeetFilterUpcoming')));
    await tester.pumpAndSettle();
    expect(find.text('Alicia C.'), findsOneWidget);
    expect(find.text('Robert W.'), findsOneWidget);
    expect(find.text('James M.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Meets keeps full status labels at narrow accessibility text sizes',
    (tester) async {
      await pumpSurface(
        tester,
        shell(
          ApprovedSellerMeetsPage(onOpenChat: () {}),
          selected: SellerNavDestination.meets,
        ),
        width: 320,
        height: 844,
        textScale: 1.3,
      );

      final upcomingTab = find.byKey(const Key('sellerMeetFilterUpcoming'));
      expect(
        find.descendant(
          of: upcomingTab,
          matching: find.byIcon(Icons.calendar_month_outlined),
        ),
        findsNothing,
      );
      for (final label in const [
        'Upcoming',
        'Today',
        'Completed',
        'Canceled',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Seller verifies the buyer PIN in the upgraded Meets sheet', (
    tester,
  ) async {
    var pinVerified = false;
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(
          onOpenChat: () {},
          onPinVerified: () => pinVerified = true,
        ),
        selected: SellerNavDestination.meets,
      ),
      width: 320,
      height: 844,
    );

    final scrollable = find
        .descendant(
          of: find.byKey(const Key('sellerMeetsScroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerMeetProductJM')),
      180,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('sellerMeetProductJM')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enter PIN'));
    await tester.tap(find.text('Enter PIN'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerPinSheet')), findsOneWidget);
    expect(find.text('Enter buyer PIN'), findsOneWidget);
    expect(find.text('Buyer PIN'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sellerBuyerPinField')),
      '11111',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('sellerVerifyBuyerPin')));
    await tester.tap(find.byKey(const Key('sellerVerifyBuyerPin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerPinError')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('sellerBuyerPinField')),
      '15230',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sellerVerifyBuyerPin')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerPinVerifiedState')), findsOneWidget);
    expect(find.text('PIN verified'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('sellerPinDone')));
    await tester.tap(find.byKey(const Key('sellerPinDone')));
    await tester.pumpAndSettle();

    expect(pinVerified, isTrue);
    expect(find.byKey(const Key('sellerPinSheet')), findsNothing);
    expect(find.text('PIN verified'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller navigation artwork is optically normalized', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(home(), selected: SellerNavDestination.home),
      width: 390,
    );

    final homeIcon = tester.widget<Image>(
      find.byKey(const Key('sellerNavHomeIcon')),
    );
    final leadsIcon = tester.widget<Image>(
      find.byKey(const Key('sellerNavLeadsIcon')),
    );
    final meetsIcon = tester.widget<Image>(
      find.byKey(const Key('sellerNavMeetsIcon')),
    );
    final chatsIcon = tester.widget<Image>(
      find.byKey(const Key('sellerNavChatsIcon')),
    );
    final moreIcon = tester.widget<Image>(
      find.byKey(const Key('sellerNavMoreIcon')),
    );

    expect(leadsIcon.width, greaterThan(homeIcon.width!));
    expect(chatsIcon.width, greaterThan(homeIcon.width!));
    expect(meetsIcon.width, greaterThan(homeIcon.width!));
    expect(moreIcon.width, closeTo(homeIcon.width!, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller conversation uses the compact approved engine', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
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
          primaryLabel: 'Review deal details',
          contactName: 'Maya Chen',
          contactRoleLabel: 'Verified Buyer',
          contactInitials: 'MC',
          viewerIsSeller: true,
        ),
        selected: SellerNavDestination.chats,
      ),
      width: 390,
      height: 844,
    );

    expect(find.byKey(const Key('approved-chat-scroll')), findsOneWidget);
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('Verified Buyer'), findsOneWidget);
    expect(find.byKey(const Key('active-deal-ipad')), findsOneWidget);
    final productTitle = tester.widget<Text>(
      find.text('iPad Air 5th Gen 64GB'),
    );
    expect(productTitle.style?.fontSize, lessThan(18));
    expect(tester.takeException(), isNull);

    await pumpSurface(
      tester,
      shell(
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
          primaryLabel: 'Review deal details',
          contactName: 'Maya Chen',
          contactRoleLabel: 'Verified Buyer',
          contactInitials: 'MC',
          viewerIsSeller: true,
        ),
        selected: SellerNavDestination.chats,
      ),
      width: 360,
      height: 1000,
      textScale: 1.6,
    );
    expect(find.byKey(const Key('active-deal-ipad')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat role badge stays on one line at enlarged text', (
    tester,
  ) async {
    await pumpSurface(
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
      width: 320,
      height: 844,
      textScale: 1.6,
    );

    final roleText = tester.widget<Text>(find.text('Verified Seller'));
    expect(roleText.maxLines, 1);
    expect(roleText.softWrap, isFalse);
    expect(roleText.overflow, TextOverflow.ellipsis);
    expect(
      find.descendant(
        of: find.byKey(const Key('approved-chat-role-badge')),
        matching: find.byType(Wrap),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller account pages use the current compact nested layout', (
    tester,
  ) async {
    final pages = <Widget>[
      ApprovedSellerProfilePage(
        sellerName: 'Northside Tech',
        onBack: () {},
        onEditProfile: () {},
      ),
      ApprovedSellerSettingsPage(
        darkMode: false,
        textSizeLabel: 'Default',
        onBack: () {},
        onEditProfile: () {},
        onThemeChanged: (_) {},
        onAccessibility: () {},
      ),
      ApprovedSellerNotificationPreferencesPage(onBack: () {}),
      ApprovedSellerEditProfilePage(
        name: 'Northside Tech',
        onNameChanged: (_) {},
        onBack: () {},
        onDone: () {},
      ),
      ApprovedSellerProfileSetupPage(onBack: () {}, onContinue: () {}),
      ApprovedSellerVerificationPage(onBack: () {}, onFinish: () {}),
      ApprovedSellerOfferHistoryPage(
        onBack: () {},
        onOpen: () {},
        sellerOfferSent: true,
        offerSelected: false,
      ),
      ApprovedSellerOfferDetailPage(onBack: () {}, onChat: () {}),
      ApprovedSellerBillingPage(onBack: () {}, onPayment: () {}),
      ApprovedSellerPaymentMethodPage(onBack: () {}, onDone: () {}),
    ];

    for (final viewport in const [
      (width: 360.0, textScale: 1.0),
      (width: 430.0, textScale: 1.0),
      (width: 360.0, textScale: 1.6),
    ]) {
      for (final page in pages) {
        await pumpSurface(
          tester,
          nestedPage(page),
          width: viewport.width,
          height: viewport.textScale > 1 ? 1100 : 932,
          textScale: viewport.textScale,
        );
        expect(find.byKey(const Key('sellerSubpageBack')), findsOneWidget);
        expect(find.text('Seller mode'), findsNothing);
        expect(
          tester.takeException(),
          isNull,
          reason: '$page at ${viewport.width} / ${viewport.textScale}x text',
        );
      }
    }
  });

  testWidgets('Seller profile pages expose shared photo change options', (
    tester,
  ) async {
    SellerProfilePhotoAction? selectedAction;
    await pumpSurface(
      tester,
      nestedPage(
        ApprovedSellerProfilePage(
          sellerName: 'Northside Tech',
          onBack: () {},
          onEditProfile: () {},
          onProfilePhotoAction: (action) => selectedAction = action,
        ),
      ),
      width: 360,
      height: 932,
    );

    await tester.tap(find.byKey(const Key('sellerProfilePhotoAction')));
    await tester.pumpAndSettle();
    expect(find.text('Change profile picture'), findsWidgets);
    expect(find.byKey(const Key('sellerPhotoTakePhoto')), findsOneWidget);
    expect(find.byKey(const Key('sellerPhotoChooseGallery')), findsOneWidget);
    expect(find.byKey(const Key('sellerPhotoRemove')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerPhotoChooseGallery')));
    await tester.pumpAndSettle();
    expect(selectedAction, SellerProfilePhotoAction.gallery);

    await pumpSurface(
      tester,
      nestedPage(
        ApprovedSellerEditProfilePage(
          name: 'Northside Tech',
          onNameChanged: (_) {},
          onBack: () {},
          onDone: () {},
        ),
      ),
      width: 360,
      height: 932,
    );
    await tester.tap(find.byKey(const Key('sellerEditProfilePhotoAction')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerPhotoTakePhoto')), findsOneWidget);
    expect(find.byKey(const Key('sellerPhotoChooseGallery')), findsOneWidget);
    expect(find.byKey(const Key('sellerPhotoRemove')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller Edit Profile uses the Buyer-style labeled inputs', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      nestedPage(
        ApprovedSellerEditProfilePage(
          name: 'Northside Tech',
          onNameChanged: (_) {},
          onBack: () {},
          onDone: () {},
        ),
      ),
      width: 360,
      height: 1100,
      textScale: 1.6,
    );

    expect(find.text('Store or seller name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(
      find.text('Email changes require account verification.'),
      findsOneWidget,
    );
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.length, 5);
    expect(fields.elementAt(1).readOnly, isTrue);
    for (final field in fields) {
      expect(field.decoration?.labelText, isNull);
      expect(field.decoration?.filled, isTrue);
    }
    final firstInput = find.byType(TextField).first;
    final emailLabel = find.text('Email');
    final relatedFieldGap =
        tester.getTopLeft(emailLabel).dy - tester.getBottomLeft(firstInput).dy;
    expect(relatedFieldGap, inInclusiveRange(6, 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reschedule remains usable at a wider Seller viewport', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(onOpenChat: () {}),
        selected: SellerNavDestination.meets,
      ),
      width: 768,
      height: 1000,
    );
    await tester.tap(find.byKey(const Key('sellerMeetProductJM')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Reschedule').first,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerMeetsScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Reschedule').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerRescheduleDialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('sellerRescheduleClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerMeetsScroll')), findsOneWidget);
  });

  testWidgets('Reschedule opens over Meets and returns to Meets', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      shell(
        ApprovedSellerMeetsPage(onOpenChat: () {}),
        selected: SellerNavDestination.meets,
      ),
      width: 390,
      height: 1000,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerMeetProductJM')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerMeetsScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('sellerMeetProductJM')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Reschedule').first,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerMeetsScroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Reschedule').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sellerRescheduleDialog')), findsOneWidget);
    expect(find.text('Reschedule meeting'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('sellerSendReschedule')),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('sellerRescheduleDialog')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final note = tester.widget<TextField>(
      find.byKey(const Key('sellerRescheduleNote')),
    );
    expect(note.decoration?.hintText, 'Add notes (optional)');
    final sendHeight = tester
        .getSize(find.byKey(const Key('sellerSendReschedule')))
        .height;
    final cancelHeight = tester
        .getSize(find.byKey(const Key('sellerCancelMeeting')))
        .height;
    expect(sendHeight, lessThanOrEqualTo(45));
    expect(cancelHeight, closeTo(sendHeight, 1));
    await tester.tap(find.byKey(const Key('sellerSendReschedule')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sellerRescheduleDialog')), findsNothing);
    expect(find.byKey(const Key('sellerMeetsScroll')), findsOneWidget);
    expect(
      find.byKey(const Key('sellerRescheduleSubmittedNotice')),
      findsOneWidget,
    );
  });

  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 980.0]) {
    testWidgets('Seller Phase 1 has no critical overflow at $width px', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        ApprovedSellerTutorialPage(onContinue: () {}, onClose: () {}),
        width: width,
      );
      expect(tester.takeException(), isNull);

      final pages = <(SellerNavDestination, Widget)>[
        (SellerNavDestination.home, home()),
        (SellerNavDestination.leads, const ApprovedSellerLeadsPage()),
        (
          SellerNavDestination.meets,
          ApprovedSellerMeetsPage(onOpenChat: () {}),
        ),
        (
          SellerNavDestination.chats,
          ApprovedSellerChatsPage(onOpenConversation: () {}),
        ),
        (SellerNavDestination.more, more()),
      ];
      for (final page in pages) {
        await pumpSurface(
          tester,
          shell(page.$2, selected: page.$1),
          width: width,
        );
        expect(
          find.byKey(const Key('sellerAppBottomNavigation')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '${page.$1} at $width');
      }
    });
  }

  testWidgets('Seller Phase 1 reflows at increased text scale', (tester) async {
    await pumpSurface(
      tester,
      ApprovedSellerTutorialPage(onContinue: () {}, onClose: () {}),
      width: 320,
      height: 1100,
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);

    await pumpSurface(
      tester,
      shell(home()),
      width: 320,
      height: 1100,
      textScale: 1.6,
    );
    expect(find.byKey(const Key('sellerAppBottomNavigation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
