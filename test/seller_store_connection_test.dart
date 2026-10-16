// Store connection tests: user-visible acknowledgement, pending review and
// retry behavior in the approved Store screen. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/features/seller/approved_seller_store_page.dart';
import 'package:hocalist/features/seller/seller_app_shell.dart';
import 'package:hocalist/features/seller/seller_bottom_navigation.dart';

import 'test_fonts.dart';

const String categoryId = '20000000-0000-4000-8000-000000000001';

class _WidgetStoreBackend implements MarketplaceStoreBackend {
  List<LocalStoreListing> listings = <LocalStoreListing>[];
  Future<StoreWriteResult> Function(LocalStoreListing listing, String key)?
  onSave;
  final List<String> saveKeys = <String>[];

  @override
  Future<List<LocalStoreListing>> loadListings() async => listings;

  @override
  Future<List<StoreCategoryOption>> loadCategories() async => const [
    StoreCategoryOption(
      id: categoryId,
      label: 'Electronics',
      scope: 'product',
      status: 'active',
    ),
  ];

  @override
  Future<StoreWriteResult> saveListing(
    LocalStoreListing listing, {
    required String operationKey,
  }) {
    saveKeys.add(operationKey);
    return onSave?.call(listing, operationKey) ??
        Future.value(
          StoreWriteResult(listing: listing.copyWith(id: 'server-1')),
        );
  }

  @override
  Future<StoreWriteResult> setListingStatus(
    String listingId,
    LocalListingStatus status, {
    required String operationKey,
    required int expectedRevision,
  }) async => StoreWriteResult(
    listing: LocalStoreListing(
      id: listingId,
      kind: LocalListingKind.product,
      title: 'Listing',
      priceLabel: r'$10',
      description: '',
      category: 'Electronics',
      categoryId: categoryId,
      revision: expectedRevision + 1,
      serviceArea: '',
      availability: '',
      status: status,
    ),
  );

  @override
  Future<StoreWriteResult> duplicateListing(
    String listingId, {
    required String operationKey,
  }) async => StoreWriteResult(
    listing: LocalStoreListing(
      id: 'server-copy',
      kind: LocalListingKind.product,
      title: 'Copy',
      priceLabel: r'$10',
      description: '',
      category: 'Electronics',
      categoryId: categoryId,
      revision: 1,
      serviceArea: '',
      availability: '',
      status: LocalListingStatus.draft,
    ),
  );

  @override
  Future<void> archiveListing(
    String listingId, {
    required String operationKey,
    required int expectedRevision,
  }) async {}
}

void main() {
  setUpAll(loadHocalistTestFonts);

  Future<void> pumpStore(
    WidgetTester tester,
    LocalMarketplaceRepository repository, {
    String? sellerName,
  }) async {
    await repository.refreshStore();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Nunito'),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(390, 900)),
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
                sellerName: sellerName,
                onStoreSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> openEditorAndPreview(
    WidgetTester tester, {
    required String title,
  }) async {
    await tester.tap(find.byKey(const Key('sellerStoreAddListing')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('sellerStoreChooseProduct')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('sellerStoreTitleField')),
      title,
    );
    await tester.enterText(
      find.byKey(const Key('sellerStorePriceField')),
      r'$25',
    );
    await tester.ensureVisible(
      find.byKey(const Key('sellerStoreCategoryPicker')),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('sellerStoreCategoryPicker')));
    await _settle(tester);
    await tester.tap(find.text('Electronics').last);
    await _settle(tester);
    await tester.ensureVisible(find.text('Preview listing'));
    await _settle(tester);
    await tester.tap(find.text('Preview listing'));
    await _settle(tester);
  }

  Future<void> tapPublish(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('sellerStorePublishListing')),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('sellerStorePublishListing')));
    await _settle(tester);
  }

  testWidgets('a failed save keeps the editor open with its inputs', (
    tester,
  ) async {
    final backend = _WidgetStoreBackend();
    var attempts = 0;
    backend.onSave = (listing, key) async {
      attempts += 1;
      if (attempts == 1) {
        throw const StoreBackendException('Your plan Store limit was reached.');
      }
      return StoreWriteResult(
        listing: listing.copyWith(
          id: 'server-1',
          revision: 1,
          pendingReview: true,
        ),
      );
    };
    final repository = LocalMarketplaceRepository(storeBackend: backend);
    addTearDown(repository.dispose);
    await pumpStore(tester, repository);

    await openEditorAndPreview(tester, title: 'Synthetic store item');
    await tapPublish(tester);

    expect(find.byKey(const Key('sellerStoreSaveError')), findsOneWidget);
    expect(find.text('Your plan Store limit was reached.'), findsWidgets);
    expect(
      find.byKey(const Key('sellerStorePublishListing')),
      findsOneWidget,
      reason: 'the editor stays open until an authoritative result exists',
    );

    await tapPublish(tester);

    expect(find.byKey(const Key('sellerStorePublishListing')), findsNothing);
    expect(find.text('Synthetic store item'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget);
    expect(backend.saveKeys, hasLength(2));
    expect(
      backend.saveKeys.toSet(),
      hasLength(1),
      reason: 'retrying the same intent keeps its operation key',
    );
  });

  testWidgets('an ambiguous save offers retry with the same intent key', (
    tester,
  ) async {
    final backend = _WidgetStoreBackend();
    var attempts = 0;
    backend.onSave = (listing, key) async {
      attempts += 1;
      if (attempts == 1) {
        throw const StoreBackendException(
          'The change could not be confirmed. Retry to check it safely.',
          ambiguous: true,
        );
      }
      return StoreWriteResult(
        listing: listing.copyWith(id: 'server-2', revision: 1),
      );
    };
    final repository = LocalMarketplaceRepository(storeBackend: backend);
    addTearDown(repository.dispose);
    await pumpStore(tester, repository);

    await openEditorAndPreview(tester, title: 'Ambiguous store item');
    await tapPublish(tester);

    expect(find.byKey(const Key('sellerStorePendingNotice')), findsOneWidget);
    expect(find.byKey(const Key('sellerStorePublishListing')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sellerStoreRetrySave')));
    await _settle(tester);

    expect(find.byKey(const Key('sellerStorePendingNotice')), findsNothing);
    expect(find.text('Ambiguous store item'), findsWidgets);
    expect(
      backend.saveKeys.toSet(),
      hasLength(1),
      reason: 'a retry reuses the original operation key',
    );
  });

  testWidgets('pending review is not presented as published', (tester) async {
    final backend = _WidgetStoreBackend();
    backend.listings = [
      LocalStoreListing(
        id: 'server-review',
        kind: LocalListingKind.product,
        title: 'Awaiting review item',
        priceLabel: r'$40',
        description: 'Synthetic',
        category: 'Electronics',
        categoryId: categoryId,
        revision: 1,
        pendingReview: true,
        serviceArea: 'Yonkers, NY',
        availability: 'Today',
        status: LocalListingStatus.active,
      ),
    ];
    final repository = LocalMarketplaceRepository(storeBackend: backend);
    addTearDown(repository.dispose);
    await repository.refreshStore();
    await pumpStore(tester, repository);

    expect(find.text('In review'), findsOneWidget);
    expect(find.text('0 published'), findsOneWidget);
    expect(find.text('Awaiting review item'), findsOneWidget);
    await tester.tap(find.text('Awaiting review item'));
    await _settle(tester);
    expect(find.text('Archive listing'), findsOneWidget);
    expect(find.text('Delete listing'), findsNothing);
    expect(
      find.text('It is not visible to buyers while it awaits review.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Archive listing'));
    await _settle(tester);
    expect(find.text('Archive this listing?'), findsOneWidget);
    expect(find.textContaining('Its record is kept.'), findsOneWidget);
    await tester.tap(find.text('Keep listing'));
    await _settle(tester);
    expect(repository.storeListings, hasLength(1));
  });

  testWidgets('backed preview uses the real seller name and no share claim', (
    tester,
  ) async {
    final backend = _WidgetStoreBackend();
    final repository = LocalMarketplaceRepository(storeBackend: backend);
    addTearDown(repository.dispose);
    await pumpStore(tester, repository, sellerName: 'Real Seller Co');

    expect(find.text('No listings yet'), findsWidgets);
    expect(find.text('Store active'), findsNothing);

    await tester.tap(find.byKey(const Key('sellerStoreMenu')));
    await _settle(tester);
    expect(find.byKey(const Key('sellerStoreShareAction')), findsOneWidget);
    expect(find.textContaining('Publish an approved listing'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerStorePreviewAction')));
    await _settle(tester);

    expect(find.text('Real Seller Co'), findsOneWidget);
    expect(find.text('Northside Tech'), findsNothing);
    expect(find.textContaining('Verified seller'), findsNothing);
    expect(find.text('Public store preview'), findsWidgets);
  });

  testWidgets('backed store without active categories disables adding', (
    tester,
  ) async {
    final backend = _NoCategoryStoreBackend();
    final repository = LocalMarketplaceRepository(storeBackend: backend);
    addTearDown(repository.dispose);
    await pumpStore(tester, repository);

    expect(
      find.byKey(const Key('sellerStoreAddListingDisabled')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sellerStoreAddListing')), findsNothing);
    expect(find.textContaining('active Store category'), findsOneWidget);
  });
}

class _NoCategoryStoreBackend extends _WidgetStoreBackend {
  @override
  Future<List<StoreCategoryOption>> loadCategories() async => const [];
}

/// Bounded settle: the approved shell can hold long-lived animations, so the
/// connection tests pump a fixed frame budget instead of waiting forever.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}
