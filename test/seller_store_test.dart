import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/features/seller/approved_seller_store_page.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'package:hocalist/features/seller/seller_bottom_navigation.dart';

import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  Future<void> pumpStore(
    WidgetTester tester,
    LocalMarketplaceRepository repository, {
    double width = 390,
    double height = 900,
    double textScale = 1,
    VoidCallback? onStoreSettings,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Nunito'),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              textScaler: TextScaler.linear(textScale),
            ),
            child: SellerAppShell(
              selected: SellerNavDestination.store,
              navigation: SellerNavigationCallbacks(
                onHome: () {},
                onStore: () {},
                onMeets: () {},
                onChats: () {},
                onMore: () {},
              ),
              onNotifications: () {},
              child: ApprovedSellerStorePage(
                repository: repository,
                onStoreSettings: onStoreSettings ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Seller navigation exposes Store and store manager content', (
    tester,
  ) async {
    final repository = LocalMarketplaceRepository();
    addTearDown(repository.dispose);

    await pumpStore(tester, repository);

    expect(find.byKey(const Key('sellerNavStore')), findsOneWidget);
    expect(find.byKey(const Key('sellerNavStoreIcon')), findsOneWidget);
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Leads'), findsNothing);
    expect(find.text('My Store'), findsOneWidget);
    expect(find.byKey(const Key('sellerStoreAddListing')), findsOneWidget);
    expect(find.text('iPad Air 5th Gen 64GB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seller can create and publish a local product listing', (
    tester,
  ) async {
    final repository = LocalMarketplaceRepository();
    addTearDown(repository.dispose);
    await pumpStore(tester, repository, height: 1000);

    await tester.tap(find.byKey(const Key('sellerStoreAddListing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerStoreChooseProduct')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sellerStoreTitleField')),
      'Gaming monitor',
    );
    await tester.enterText(
      find.byKey(const Key('sellerStoreCategoryField')),
      'Electronics',
    );
    await tester.enterText(
      find.byKey(const Key('sellerStorePriceField')),
      r'$280',
    );
    await tester.scrollUntilVisible(
      find.text('Preview listing'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Preview listing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerStorePublishListing')));
    await tester.pumpAndSettle();

    expect(find.text('Gaming monitor'), findsOneWidget);
    expect(
      repository.storeListings.any(
        (listing) =>
            listing.title == 'Gaming monitor' &&
            listing.status == LocalListingStatus.active,
      ),
      isTrue,
    );
    expect(find.text('Listing published to your store.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Store filters and listing status actions work locally', (
    tester,
  ) async {
    final repository = LocalMarketplaceRepository();
    addTearDown(repository.dispose);
    await pumpStore(tester, repository);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('Pressure washing'), findsOneWidget);
    expect(find.text('iPad Air 5th Gen 64GB'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('sellerStoreListing-listing-ipad-air')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sellerStoreToggleListing')));
    await tester.pumpAndSettle();

    expect(
      repository.storeListings
          .firstWhere((listing) => listing.id == 'listing-ipad-air')
          .status,
      LocalListingStatus.paused,
    );
    expect(find.text('Listing paused.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('Store remains usable at $width logical pixels', (
      tester,
    ) async {
      final repository = LocalMarketplaceRepository();
      addTearDown(repository.dispose);
      await pumpStore(tester, repository, width: width, textScale: 1.3);

      expect(find.text('My Store'), findsOneWidget);
      expect(find.byKey(const Key('sellerStoreScroll')), findsOneWidget);
      expect(
        find.byKey(const Key('sellerAppBottomNavigation')),
        findsOneWidget,
      );
      final exception = tester.takeException();
      if (exception is FlutterError) {
        fail(exception.toStringDeep());
      }
      expect(exception, isNull);
    });
  }
}
