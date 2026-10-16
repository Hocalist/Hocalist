import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/repositories.dart';
import 'package:hocalist/domain/phase2/store_listings.dart';
import 'package:hocalist/features/saved/public_seller_listings.dart';

class ListingsFake implements StoreListingRepository {
  late Future<RepositoryResult<PageSlice<PublicStoreListing>>> Function(
    String,
    String?,
  )
  load;
  @override
  Future<RepositoryResult<PageSlice<PublicStoreListing>>>
  fetchPublicSellerListings({
    required String sellerProfileId,
    ListingKind? kind,
    PageQuery page = PageQuery.standard,
  }) => load(sellerProfileId, page.cursor);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PublicStoreListing listing(String seller, {String id = 'listing'}) =>
    PublicStoreListing(
      id: id,
      sellerProfileId: seller,
      kind: ListingKind.product,
      title: 'Published tablet',
      description: 'Includes the original charger.',
      categoryLabel: 'Electronics',
      priceLabel: '\$250',
    );
void main() {
  Future<void> pump(
    WidgetTester tester,
    ListingsFake repo, {
    String seller = 'seller',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublicSellerListings(
              repository: repo,
              sellerProfileId: seller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'published details expand; pagination failure retains items and cursor',
    (tester) async {
      final repo = ListingsFake();
      final cursors = <String?>[];
      repo.load = (seller, cursor) async {
        cursors.add(cursor);
        if (cursor != null) {
          return const RepositoryFailureResult(NetworkError());
        }
        return RepositorySuccess(
          PageSlice(items: [listing(seller)], nextCursor: 'next'),
        );
      };
      await pump(tester, repo);
      await tester.tap(find.text('Published tablet'));
      await tester.pumpAndSettle();
      expect(find.text('Includes the original charger.'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Load more listings'));
        await tester.pumpAndSettle();
        expect(find.text('Published tablet'), findsOneWidget);
      }
      expect(cursors, [null, 'next', 'next']);
    },
  );
  testWidgets('a mismatched seller is not rendered or described as empty', (
    tester,
  ) async {
    final repo = ListingsFake()
      ..load = (_, _) async =>
          RepositorySuccess(PageSlice(items: [listing('other')]));
    await pump(tester, repo);
    expect(find.text('Published tablet'), findsNothing);
    expect(find.text('No published listings available.'), findsNothing);
    expect(find.text('Retry listings'), findsOneWidget);
  });
  testWidgets('seller replacement discards the previous in-flight page', (
    tester,
  ) async {
    final late = Completer<RepositoryResult<PageSlice<PublicStoreListing>>>();
    final repo = ListingsFake()
      ..load = (seller, _) => seller == 'a'
          ? late.future
          : Future.value(RepositorySuccess(PageSlice(items: [])));
    await tester.pumpWidget(
      MaterialApp(
        home: PublicSellerListings(repository: repo, sellerProfileId: 'a'),
      ),
    );
    await tester.pump();
    await pump(tester, repo, seller: 'b');
    late.complete(RepositorySuccess(PageSlice(items: [listing('a')])));
    await tester.pumpAndSettle();
    expect(find.text('Published tablet'), findsNothing);
  });
}
