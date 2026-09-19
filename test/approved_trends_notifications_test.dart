import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/approved_replica_metrics.dart';
import 'package:hocalist/features/approved/trends_notifications_pages.dart';
import 'package:hocalist/main.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

const _writeProof = bool.fromEnvironment(
  'HOCALIST_WRITE_TRENDS_NOTIFICATIONS_PROOF',
);

const _sellerCommerceProofData =
    <
      ({
        String name,
        String price,
        String savings,
        String badge,
        String deals,
        String response,
      })
    >[
      (
        name: 'Northside Tech',
        price: '\$820',
        savings: 'Save \$180',
        badge: 'Top Rated Seller',
        deals: '230+ deals completed',
        response: 'Usually responds in a few hours',
      ),
      (
        name: 'Gadget Hub',
        price: '\$835',
        savings: 'Save \$165',
        badge: 'Great Deal',
        deals: '150+ deals completed',
        response: 'Responds within 2 hours',
      ),
      (
        name: 'Prime Tech Solutions',
        price: '\$845',
        savings: 'Save \$155',
        badge: 'Fast Responder',
        deals: '120+ deals completed',
        response: 'Usually responds in a few hours',
      ),
      (
        name: 'Tech World NY',
        price: '\$860',
        savings: 'Save \$140',
        badge: 'Good Value',
        deals: '90+ deals completed',
        response: 'Responds within 3 hours',
      ),
      (
        name: 'Digital Depot',
        price: '\$875',
        savings: 'Save \$125',
        badge: 'Trusted Seller',
        deals: '110+ deals completed',
        response: 'Usually responds in a few hours',
      ),
    ];

class _ProjectFileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith('assets/')) {
      return rootBundle.load(key);
    }
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Future<void> _pumpApprovedSurface(
  WidgetTester tester,
  Widget child, {
  required double width,
  double textScale = 1,
  double height = 2600,
  GlobalKey? boundaryKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;

  final content = ColoredBox(
    color: HocalistTheme.background,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: KeyedSubtree(
        key: const ValueKey('approved-surface'),
        child: child,
      ),
    ),
  );

  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _ProjectFileAssetBundle(),
      child: MaterialApp(
        key: ObjectKey(child),
        debugShowCheckedModeBanner: false,
        theme: HocalistTheme.light,
        builder: (context, appChild) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: appChild ?? const SizedBox.shrink(),
          );
        },
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: boundaryKey == null
                  ? content
                  : RepaintBoundary(key: boundaryKey, child: content),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSingleRenderedLine(
  WidgetTester tester,
  String text, {
  Finder? within,
}) {
  final finder = within == null
      ? find.text(text)
      : find.descendant(of: within, matching: find.text(text));
  final widget = tester.widget<Text>(finder.first);
  expect(widget.maxLines, 1);
  expect(widget.softWrap, isFalse);
}

void main() {
  setUpAll(loadHocalistTestFonts);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets('approved pages inherit the actual app font family', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
      width: 390,
    );

    final saving = tester.widget<Text>(find.text('Saving'));
    expect(saving.style?.fontFamily, HocalistTheme.appFontFamily);
    expect(
      find.text('Skip the Rewards & save on current offers'),
      findsOneWidget,
    );
  });

  testWidgets('top-level Buyer header keeps one canonical visual contract', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    HocalistGlobalHeader header() {
      return HocalistGlobalHeader(
        role: UserRole.buyer,
        accent: HocalistTheme.actionBlue,
        onNotifications: () {},
      );
    }

    for (final width in <double>[320, 390, 600]) {
      await _pumpApprovedSurface(tester, header(), width: width, height: 180);
      final metrics = ApprovedReplicaMetrics.resolve(
        availableWidth: width,
        textScaler: TextScaler.noScaling,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('buyer-top-level-header-logo')),
        ),
        Size(metrics.artSize(88), metrics.artSize(54)),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('buyer-top-level-header-mode')))
            .height,
        greaterThanOrEqualTo(metrics.geometry(38)),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('buyer-top-level-header-notifications')),
        ),
        Size(metrics.artSize(44), metrics.artSize(44)),
      );
      final notificationArtwork = tester.widget<BuyerAssetIcon>(
        find.descendant(
          of: find.byKey(
            const ValueKey('buyer-top-level-header-notifications'),
          ),
          matching: find.byType(BuyerAssetIcon),
        ),
      );
      expect(notificationArtwork.slotSize, metrics.artSize(32));
      expect(find.text('Buyer mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('global buyer navigation matches approved replica geometry', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpSignedIn({
      required String role,
      required String page,
      required double width,
      required double height,
    }) async {
      SharedPreferences.setMockInitialValues({
        'hocalist.hasSession': true,
        'hocalist.authenticated': true,
        'hocalist.role': role,
        'hocalist.page': page,
      });
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(HocalistPrototype(key: UniqueKey()));
      await tester.pumpAndSettle();
    }

    const buyerNavKey = ValueKey('global-buyer-bottom-navigation');
    const buyerNavContentKey = ValueKey(
      'global-buyer-bottom-navigation-content',
    );
    const topLevelHeaderKey = ValueKey('buyer-top-level-header');

    await pumpSignedIn(
      role: 'buyer',
      page: 'hocatrends',
      width: 390,
      height: 844,
    );
    expect(find.byKey(buyerNavKey), findsOneWidget);
    expect(tester.getSize(find.byKey(buyerNavKey)).height, closeTo(58.5, 0.01));
    expect(find.text('See Sellers'), findsNWidgets(5));
    final finalTrendCard = find.byKey(const ValueKey('approved-trend-card-5'));
    await tester.ensureVisible(finalTrendCard);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(finalTrendCard).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(buyerNavKey)).dy),
    );
    expect(tester.takeException(), isNull);

    await pumpSignedIn(
      role: 'buyer',
      page: 'hocatrends',
      width: 320,
      height: 693,
    );
    expect(
      tester.getSize(find.byKey(buyerNavKey)).height,
      closeTo(58.5 * 320 / 390, 0.01),
    );
    expect(tester.getSize(find.byKey(buyerNavContentKey)).width, 320);
    expect(tester.takeException(), isNull);

    await pumpSignedIn(
      role: 'buyer',
      page: 'hocatrends',
      width: 600,
      height: 1000,
    );
    expect(tester.getSize(find.byKey(buyerNavKey)).height, closeTo(58.5, 0.01));
    expect(tester.getSize(find.byKey(buyerNavContentKey)).width, 600);
    expect(tester.getCenter(find.byKey(buyerNavContentKey)).dx, 300);
    final metrics600 = ApprovedReplicaMetrics.resolve(
      availableWidth: 600,
      textScaler: TextScaler.noScaling,
    );
    expect(
      tester.getSize(find.byKey(topLevelHeaderKey)).width,
      closeTo(
        metrics600.innerContentMaxWidth(referenceHorizontalInset: 18),
        0.01,
      ),
    );
    expect(tester.getCenter(find.byKey(topLevelHeaderKey)).dx, 300);
    expect(tester.takeException(), isNull);

    await pumpSignedIn(
      role: 'buyer',
      page: 'hocatrends',
      width: 768,
      height: 1024,
    );
    final metrics768 = ApprovedReplicaMetrics.resolve(
      availableWidth: 768,
      textScaler: TextScaler.noScaling,
    );
    expect(
      tester.getSize(find.byKey(topLevelHeaderKey)).width,
      closeTo(
        metrics768.innerContentMaxWidth(referenceHorizontalInset: 18),
        0.01,
      ),
    );
    expect(tester.getCenter(find.byKey(topLevelHeaderKey)).dx, 384);
    expect(tester.takeException(), isNull);

    await pumpSignedIn(
      role: 'seller',
      page: 'sellerDashboard',
      width: 390,
      height: 844,
    );
    final sellerNavigation = find.byKey(
      const ValueKey('sellerAppBottomNavigation'),
    );
    expect(sellerNavigation, findsOneWidget);
    expect(tester.getSize(sellerNavigation).height, greaterThan(50));
    expect(find.byKey(buyerNavKey), findsNothing);
    expect(find.byKey(topLevelHeaderKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390 layouts match approved vertical density', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
      width: 390,
      height: 844,
    );

    expect(find.text('See Sellers'), findsNWidgets(5));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('approved-trend-card-1')))
          .height,
      inInclusiveRange(83, 85),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('approved-surface'))).height,
      lessThan(710),
    );
    expect(
      tester.getBottomRight(find.text('See Sellers').last).dy,
      lessThan(800),
    );
    expect(tester.widget<Text>(find.text('Saving')).style?.fontSize, 20);
    expect(tester.takeException(), isNull);

    await _pumpApprovedSurface(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}),
      width: 390,
      height: 844,
    );

    expect(find.text('Rewards will be paid on May 13'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('approved-surface'))).height,
      lessThan(710),
    );
    expect(
      tester.getBottomRight(find.text('Rewards will be paid on May 13')).dy,
      lessThan(800),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('default replica metrics hold across phone and tablet widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final widths = <double>[304, 320, 360, 390, 430, 600, 768, 980];

    for (final width in widths) {
      final resolvedMetrics = ApprovedReplicaMetrics.resolve(
        availableWidth: width,
        textScaler: TextScaler.noScaling,
      );
      final expectedScale = resolvedMetrics.typographyScale;
      await _pumpApprovedSurface(
        tester,
        ApprovedHocatrendsPage(
          accent: HocalistTheme.actionBlue,
          onSeeSellers: () {},
        ),
        width: width,
      );
      expect(
        tester.widget<Text>(find.text('Saving')).style?.fontSize,
        closeTo(20 * expectedScale, 0.001),
      );
      expect(
        tester.widget<Text>(find.text('Saving')).style?.fontWeight,
        FontWeight.w800,
      );
      expect(
        (tester.getTopLeft(find.text('Saving')).dy -
                tester.getTopLeft(find.text('Opportunities')).dy)
            .abs(),
        lessThan(2),
      );
      if (width == 320) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('approved-trend-card-1')))
              .height,
          inInclusiveRange(68, 70),
        );
      }
      expect(
        tester
            .getSize(find.byKey(const ValueKey('approved-replica-content')))
            .width,
        closeTo((width - 32).clamp(0, resolvedMetrics.contentMaxWidth), 0.001),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Hocatrends at $width logical pixels',
      );

      await _pumpApprovedSurface(
        tester,
        ApprovedHocatrendsPickedSellersPage(onBack: () {}, onChatSeller: () {}),
        width: width,
        height: 3200,
      );
      final expectedSellerNameSize = 16 * expectedScale;
      expect(
        tester.widget<Text>(find.text('Northside Tech')).style?.fontSize,
        closeTo(expectedSellerNameSize, 0.001),
      );
      expect(
        tester.widget<Text>(find.text('Northside Tech')).style?.fontWeight,
        FontWeight.w800,
      );
      final controlsY = <double>[
        tester.getCenter(find.text('Filters')).dy,
        tester.getCenter(find.text('Sort by: Best deal')).dy,
        tester.getCenter(find.byTooltip('List view')).dy,
      ];
      expect(
        controlsY.reduce((a, b) => a > b ? a : b) -
            controlsY.reduce((a, b) => a < b ? a : b),
        lessThan(3),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('approved-replica-content')))
            .width,
        closeTo((width - 32).clamp(0, resolvedMetrics.contentMaxWidth), 0.001),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'picked sellers at $width logical pixels',
      );

      await _pumpApprovedSurface(
        tester,
        ApprovedBuyerNotificationsPage(onBack: () {}),
        width: width,
      );
      expect(
        tester.widget<Text>(find.text('Recent activity')).style?.fontSize,
        closeTo(16 * expectedScale, 0.001),
      );
      expect(
        tester.widget<Text>(find.text('Recent activity')).style?.fontWeight,
        FontWeight.w800,
      );
      expect(
        (tester.getCenter(find.text('All')).dy -
                tester.getCenter(find.text('Payouts')).dy)
            .abs(),
        lessThan(2),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('approved-replica-content')))
            .width,
        closeTo((width - 32).clamp(0, resolvedMetrics.contentMaxWidth), 0.001),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'buyer notifications at $width logical pixels',
      );
    }
  });

  testWidgets('320 default keeps the approved compact composition', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
      width: 320,
      height: 693,
    );

    expect(find.text('See Sellers'), findsNWidgets(5));
    expect(
      (tester.getTopLeft(find.text('Saving')).dy -
              tester.getTopLeft(find.text('Opportunities')).dy)
          .abs(),
      lessThan(2),
    );
    for (final button in find.text('See Sellers').evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)).height, lessThan(20));
    }
    expect(
      tester.getBottomRight(find.text('See Sellers').last).dy,
      lessThan(650),
    );
    expect(tester.takeException(), isNull);

    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPickedSellersPage(onBack: () {}, onChatSeller: () {}),
      width: 320,
      height: 693,
    );

    expect(find.text('Chat Seller'), findsNWidgets(5));
    expect(find.text('Digital Depot'), findsOneWidget);
    final controlsY = <double>[
      tester.getCenter(find.text('Filters')).dy,
      tester.getCenter(find.text('Sort by: Best deal')).dy,
      tester.getCenter(find.byTooltip('List view')).dy,
    ];
    expect(
      controlsY.reduce((a, b) => a > b ? a : b) -
          controlsY.reduce((a, b) => a < b ? a : b),
      lessThan(3),
    );
    _expectSingleRenderedLine(tester, 'Chat Seller');
    _expectSingleRenderedLine(tester, 'Northside Tech');
    _expectSingleRenderedLine(tester, 'Tech World NY');
    _expectSingleRenderedLine(tester, 'Usually responds in a few hours');
    expect(tester.takeException(), isNull);

    await _pumpApprovedSurface(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () {}),
      width: 320,
      height: 693,
    );

    expect(find.text('Payouts'), findsOneWidget);
    expect(
      (tester.getCenter(find.text('All')).dy -
              tester.getCenter(find.text('Payouts')).dy)
          .abs(),
      lessThan(2),
    );
    expect(tester.getTopRight(find.text('Payouts')).dx, lessThan(304));
    expect(find.text('Rewards will be paid on May 13'), findsOneWidget);
    expect(
      tester.getBottomRight(find.text('Rewards will be paid on May 13')).dy,
      lessThan(650),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picked seller cards keep commerce content separated', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[304, 320, 360, 390, 430]) {
      await _pumpApprovedSurface(
        tester,
        ApprovedHocatrendsPickedSellersPage(onBack: () {}, onChatSeller: () {}),
        width: width,
        height: 3200,
      );

      for (final seller in _sellerCommerceProofData) {
        final card = find.byKey(
          ValueKey('approved-seller-card-${seller.name}'),
        );
        final chatText = find.descendant(
          of: card,
          matching: find.text('Chat Seller'),
        );
        final chatButton = find.ancestor(
          of: chatText,
          matching: find.byType(FilledButton),
        );
        final price = find.descendant(
          of: card,
          matching: find.text(seller.price),
        );
        final savings = find.descendant(
          of: card,
          matching: find.text(seller.savings),
        );
        final badge = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_ApprovedSellerBadge',
          ),
        );
        final deals = find.descendant(
          of: card,
          matching: find.text(seller.deals),
        );
        final response = find.descendant(
          of: card,
          matching: find.text(seller.response),
        );

        for (final label in <String>[
          seller.name,
          seller.price,
          seller.savings,
          seller.badge,
          seller.deals,
          seller.response,
          'Chat Seller',
        ]) {
          _expectSingleRenderedLine(tester, label, within: card);
        }
        expect(
          tester.getRect(chatButton).overlaps(tester.getRect(price)),
          isFalse,
        );
        expect(
          tester.getRect(chatButton).overlaps(tester.getRect(savings)),
          isFalse,
        );
        expect(
          (tester.getRect(price).left - tester.getRect(savings).left).abs(),
          lessThan(1),
        );
        expect(
          tester.getRect(badge).width,
          lessThan(tester.getRect(card).width * .36),
        );
        expect(
          tester.getRect(response).left - tester.getRect(deals).left,
          lessThan(tester.getRect(card).width * .44),
        );
      }
      expect(tester.takeException(), isNull, reason: 'Seller cards at $width');
    }
  });

  testWidgets('Large XL and external text scales reflow without overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pages = <Widget>[
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
      ApprovedHocatrendsPickedSellersPage(onBack: () {}, onChatSeller: () {}),
      ApprovedBuyerNotificationsPage(onBack: () {}),
    ];

    final cases = <({double width, double scale, String label})>[
      (width: 320, scale: 1.15, label: 'Large narrow'),
      (width: 320, scale: 1.3, label: 'XL narrow'),
      (width: 390, scale: 1.15, label: 'Large reference'),
      (width: 390, scale: 1.3, label: 'XL reference'),
      (width: 360, scale: 1.6, label: 'external 1.6'),
    ];

    for (final testCase in cases) {
      for (final page in pages) {
        await _pumpApprovedSurface(
          tester,
          page,
          width: testCase.width,
          height: 6000,
          textScale: testCase.scale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} at ${testCase.label}',
        );
      }
    }
  });

  testWidgets('approved callbacks and filters preserve current behavior', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var seeSellers = 0;
    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () => seeSellers++,
      ),
      width: 390,
    );
    await tester.tap(find.text('See Sellers').first);
    await tester.pump();
    expect(seeSellers, 1);

    var back = 0;
    var chat = 0;
    await _pumpApprovedSurface(
      tester,
      ApprovedHocatrendsPickedSellersPage(
        onBack: () => back++,
        onChatSeller: () => chat++,
      ),
      width: 390,
      height: 3200,
    );
    await tester.tap(find.byTooltip('Back to Hocatrends'));
    await tester.tap(find.text('Chat Seller').first);
    await tester.tap(find.text('Filters'));
    await tester.pump();
    expect(back, 1);
    expect(chat, 1);
    expect(find.text('Verified sellers'), findsOneWidget);

    await _pumpApprovedSurface(
      tester,
      ApprovedBuyerNotificationsPage(onBack: () => back++),
      width: 390,
    );
    await tester.tap(find.byTooltip('Back to home'));
    await tester.tap(find.text('Reviews'));
    await tester.pump();
    expect(back, 2);
    expect(find.text('You earned a new review'), findsNWidgets(2));
    expect(find.text('Northside Tech sent you a new offer'), findsNothing);
  });

  testWidgets('write approved page proof renders', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final output = Directory(
      '${Directory.systemTemp.path}\\hocalist-trends-notifications-proof',
    );
    await output.create(recursive: true);

    final pages = <String, Widget>{
      'hocatrends-render.png': ApprovedHocatrendsPage(
        accent: HocalistTheme.actionBlue,
        onSeeSellers: () {},
      ),
      'picked-sellers-render.png': ApprovedHocatrendsPickedSellersPage(
        onBack: () {},
        onChatSeller: () {},
      ),
      'buyer-notifications-render.png': ApprovedBuyerNotificationsPage(
        onBack: () {},
      ),
    };

    for (final entry in pages.entries) {
      final boundaryKey = GlobalKey();
      await _pumpApprovedSurface(
        tester,
        entry.value,
        width: 426,
        height: 2800,
        boundaryKey: boundaryKey,
      );
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${output.path}\\${entry.key}',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }
  }, skip: !_writeProof);
}
