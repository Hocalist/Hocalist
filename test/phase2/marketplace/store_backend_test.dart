// Store wiring tests: repository acknowledgement/lifecycle semantics and the
// Phase 2 Store backend mapping. Fakes only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_store_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';

import 'support/marketplace_fakes.dart';

class FakeStoreBackend implements MarketplaceStoreBackend {
  Future<List<LocalStoreListing>> Function()? onLoad;
  Future<List<StoreCategoryOption>> Function()? onCategories;
  Future<StoreWriteResult> Function(LocalStoreListing listing, String key)?
  onSave;
  Future<StoreWriteResult> Function(
    String id,
    LocalListingStatus status,
    String key,
    int revision,
  )?
  onStatus;
  Future<StoreWriteResult> Function(String id, String key)? onDuplicate;
  Future<void> Function(String id, String key, int revision)? onArchive;

  final List<String> saveKeys = <String>[];
  final List<int> saveRevisions = <int>[];
  final List<int> statusRevisions = <int>[];
  final List<int> archiveRevisions = <int>[];

  @override
  Future<List<LocalStoreListing>> loadListings() =>
      onLoad?.call() ?? Future.value(const []);

  @override
  Future<List<StoreCategoryOption>> loadCategories() =>
      onCategories?.call() ?? Future.value(const []);

  @override
  Future<StoreWriteResult> saveListing(
    LocalStoreListing listing, {
    required String operationKey,
  }) {
    saveKeys.add(operationKey);
    saveRevisions.add(listing.revision);
    return onSave?.call(listing, operationKey) ??
        Future.value(StoreWriteResult(listing: listing));
  }

  @override
  Future<StoreWriteResult> setListingStatus(
    String listingId,
    LocalListingStatus status, {
    required String operationKey,
    required int expectedRevision,
  }) {
    statusRevisions.add(expectedRevision);
    return onStatus?.call(listingId, status, operationKey, expectedRevision) ??
        Future.value(
          StoreWriteResult(
            listing: localListing(id: listingId, status: status),
          ),
        );
  }

  @override
  Future<StoreWriteResult> duplicateListing(
    String listingId, {
    required String operationKey,
  }) =>
      onDuplicate?.call(listingId, operationKey) ??
      Future.value(StoreWriteResult(listing: localListing(id: 'server-copy')));

  @override
  Future<void> archiveListing(
    String listingId, {
    required String operationKey,
    required int expectedRevision,
  }) {
    archiveRevisions.add(expectedRevision);
    return onArchive?.call(listingId, operationKey, expectedRevision) ??
        Future.value();
  }
}

LocalStoreListing localListing({
  String id = '',
  String title = 'Synthetic listing',
  LocalListingStatus status = LocalListingStatus.draft,
  String category = 'Electronics',
  String? categoryId = categoryIdFixture,
  int revision = 0,
  bool pendingReview = false,
}) => LocalStoreListing(
  id: id,
  kind: LocalListingKind.product,
  title: title,
  priceLabel: r'$10',
  description: 'Synthetic',
  category: category,
  categoryId: categoryId,
  revision: revision,
  pendingReview: pendingReview,
  serviceArea: 'Yonkers, NY',
  availability: 'Today',
  status: status,
);

const String categoryIdFixture = '20000000-0000-4000-8000-000000000001';

void main() {
  group('LocalMarketplaceRepository Store acknowledgement', () {
    test('prototype mode keeps local defaults and local ids', () async {
      final repository = LocalMarketplaceRepository();
      expect(repository.isStoreBacked, isFalse);
      expect(repository.storeListings, isNotEmpty);
      final saved = await repository.saveStoreListing(localListing());
      expect(saved.id, startsWith('local-listing-'));
      expect(repository.storeListings.first.id, saved.id);
    });

    test('refreshStore loads listings and categories', () async {
      final backend = FakeStoreBackend();
      backend.onLoad = () async => [localListing(id: 'server-1')];
      backend.onCategories = () async => const [
        StoreCategoryOption(
          id: categoryIdFixture,
          label: 'Electronics',
          scope: 'product',
          status: 'active',
        ),
      ];
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      final refresh = repository.refreshStore();
      expect(repository.storeLoading, isTrue);
      await refresh;
      expect(repository.storeLoading, isFalse);
      expect(repository.storeListings.single.id, 'server-1');
      expect(repository.storeCategories.single.label, 'Electronics');
      expect(repository.storeError, isNull);
    });

    test('an older refresh cannot replace a newer cache', () async {
      final gate = Completer<void>();
      var call = 0;
      final backend = FakeStoreBackend();
      backend.onLoad = () async {
        call += 1;
        if (call == 1) {
          await gate.future;
          return [localListing(id: 'stale')];
        }
        return [localListing(id: 'fresh')];
      };
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      final stale = repository.refreshStore();
      await repository.refreshStore();
      expect(repository.storeListings.single.id, 'fresh');
      gate.complete();
      await stale;
      expect(repository.storeListings.single.id, 'fresh');
    });

    test('save reports success only after the authoritative result', () async {
      final gate = Completer<void>();
      final backend = FakeStoreBackend();
      backend.onSave = (listing, key) async {
        await gate.future;
        return StoreWriteResult(
          listing: localListing(
            id: 'server-new',
            title: listing.title,
            revision: 1,
            pendingReview: true,
          ),
        );
      };
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      final pending = repository.saveStoreListing(localListing());
      expect(repository.storeListings.single.pendingSync, isTrue);
      expect(repository.storeListings.single.id, startsWith('pending-'));
      gate.complete();
      final saved = await pending;
      expect(saved.id, 'server-new');
      expect(repository.storeListings.single.id, 'server-new');
      expect(repository.storeListings.single.pendingSync, isFalse);
      expect(repository.storeListings.single.pendingReview, isTrue);
    });

    test('a definitive failure reverts and rethrows', () async {
      final backend = FakeStoreBackend();
      backend.onSave = (listing, key) async =>
          throw const StoreBackendException(
            'Your plan Store limit was reached.',
          );
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      await expectLater(
        repository.saveStoreListing(localListing()),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.message,
            'message',
            'Your plan Store limit was reached.',
          ),
        ),
      );
      expect(repository.storeListings, isEmpty);
      expect(repository.storeError, 'Your plan Store limit was reached.');
    });

    test(
      'an ambiguous failure keeps the pending row for a safe retry',
      () async {
        final backend = FakeStoreBackend();
        var attempt = 0;
        backend.onSave = (listing, key) async {
          attempt += 1;
          if (attempt == 1) {
            throw const StoreBackendException(
              'The change could not be confirmed. Retry to check it safely.',
              ambiguous: true,
            );
          }
          return StoreWriteResult(
            listing: localListing(id: 'server-confirmed', title: listing.title),
          );
        };
        final repository = LocalMarketplaceRepository(storeBackend: backend);
        final key = LocalMarketplaceRepository.newStoreOperationKey(
          'store-save',
        );
        await expectLater(
          repository.saveStoreListing(localListing(), operationKey: key),
          throwsA(
            isA<StoreBackendException>().having(
              (error) => error.ambiguous,
              'ambiguous',
              isTrue,
            ),
          ),
        );
        expect(repository.storeListings.single.pendingSync, isTrue);
        final confirmed = await repository.saveStoreListing(
          repository.storeListings.single,
          operationKey: key,
        );
        expect(confirmed.id, 'server-confirmed');
        expect(backend.saveKeys, [
          key,
          key,
        ], reason: 'same intent keeps its key');
        expect(repository.storeListings.single.pendingSync, isFalse);
      },
    );

    test('a failed status change restores the previous listing', () async {
      final backend = FakeStoreBackend();
      backend.onLoad = () async => [
        localListing(
          id: 'server-1',
          status: LocalListingStatus.draft,
          revision: 2,
        ),
      ];
      backend.onStatus = (id, status, key, revision) async =>
          throw const StoreBackendException('Not permitted');
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      await repository.refreshStore();
      await expectLater(
        repository.updateStoreListingStatus(
          'server-1',
          LocalListingStatus.active,
        ),
        throwsA(isA<StoreBackendException>()),
      );
      expect(repository.storeListings.single.status, LocalListingStatus.draft);
      expect(repository.storeError, 'Not permitted');
      expect(backend.statusRevisions.single, 2);
    });

    test('an ambiguous delete restores a visibly pending row', () async {
      final backend = FakeStoreBackend();
      backend.onLoad = () async => [localListing(id: 'server-1', revision: 4)];
      backend.onArchive = (id, key, revision) async =>
          throw const StoreBackendException('Unconfirmed', ambiguous: true);
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      await repository.refreshStore();
      await expectLater(
        repository.deleteStoreListing('server-1'),
        throwsA(isA<StoreBackendException>()),
      );
      expect(repository.storeListings.single.id, 'server-1');
      expect(repository.storeListings.single.pendingSync, isTrue);
      expect(backend.archiveRevisions.single, 4);
    });

    test('out-of-order writes keep the newest result', () async {
      final first = Completer<void>();
      var call = 0;
      final backend = FakeStoreBackend();
      backend.onLoad = () async => [
        localListing(id: 'server-1', title: 'Base', revision: 1),
      ];
      backend.onSave = (listing, key) async {
        call += 1;
        if (call == 1) {
          await first.future;
          return StoreWriteResult(
            listing: localListing(id: 'server-1', title: 'Older write'),
          );
        }
        return StoreWriteResult(
          listing: localListing(id: 'server-1', title: 'Newer write'),
        );
      };
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      await repository.refreshStore();
      final older = repository.saveStoreListing(
        localListing(id: 'server-1', title: 'Older write', revision: 1),
      );
      await repository.saveStoreListing(
        localListing(id: 'server-1', title: 'Newer write', revision: 1),
      );
      expect(repository.storeListings.single.title, 'Newer write');
      first.complete();
      await older;
      expect(
        repository.storeListings.single.title,
        'Newer write',
        reason: 'a stale completion must not overwrite a newer mutation',
      );
    });

    test('disposing during a load applies nothing', () async {
      final gate = Completer<void>();
      final backend = FakeStoreBackend();
      backend.onLoad = () async {
        await gate.future;
        return [localListing(id: 'late')];
      };
      final repository = LocalMarketplaceRepository(storeBackend: backend);
      final pending = repository.refreshStore();
      repository.dispose();
      gate.complete();
      await pending;
      expect(repository.storeListings, isEmpty);
    });
  });

  group('Phase2MarketplaceStoreBackend', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MarketplaceDataAdapter adapter;
    late Phase2MarketplaceStoreBackend backend;

    setUp(() {
      session = FakeMarketplaceSession(sellerId);
      transport = FakeMarketplaceTransport();
      adapter = MarketplaceDataAdapter(transport: transport, session: session);
      backend = Phase2MarketplaceStoreBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
    });

    test('rejected active listings stay private across persistence', () async {
      transport.handler = (call) => data(
        pageJson([listingJson(status: 'active', moderationStatus: 'rejected')]),
      );
      final listing = (await backend.loadListings()).single;
      expect(listing.rejected, isTrue);
      expect(listing.isPubliclyVisible, isFalse);
      final restored = LocalStoreListing.fromJson(listing.toJson()).copyWith();
      expect(restored.rejected, isTrue);
      expect(restored.isPubliclyVisible, isFalse);
    });

    test(
      'loads and maps listings with category identity and revision',
      () async {
        transport.handler = (call) => data(
          pageJson([
            listingJson(status: 'active', moderationStatus: 'approved'),
          ]),
        );
        final listings = await backend.loadListings();
        expect(listings.single.categoryId, categoryId);
        expect(listings.single.revision, 1);
        expect(listings.single.pendingReview, isFalse);
        expect(listings.single.category, 'Electronics');
      },
    );

    test('create sends the selected category id and operation key', () async {
      transport.handler = (call) => data(listingJson(status: 'draft'));
      final result = await backend.saveListing(
        localListing(title: 'New listing'),
        operationKey: 'intent-key-1',
      );
      expect(result.listing.id, listingId);
      final create = transport.calls.last;
      expect(create.params['p_operation'], 'store.create');
      expect(create.params['p_key'], 'intent-key-1');
      final input = create.params['p_input']! as Map<String, Object?>;
      expect(input['category_id'], categoryId);
      expect(input['publish_intent'], 'draft');
      expect(
        transport.calls.any((call) => call.function == 'marketplace_catalogue'),
        isFalse,
        reason: 'category identity must not be resolved from labels',
      );
    });

    test(
      'update carries the original revision and never refreshes it',
      () async {
        transport.handler = (call) =>
            data(listingJson(status: 'draft', revision: 4));
        final result = await backend.saveListing(
          localListing(id: listingId, revision: 3),
          operationKey: 'intent-key-2',
        );
        expect(result.listing.revision, 4);
        final update = transport.calls.last;
        expect(update.params['p_operation'], 'store.update');
        final input = update.params['p_input']! as Map<String, Object?>;
        expect(input['expected_revision'], 3);
        expect(
          transport.calls.any(
            (call) => call.function == 'marketplace_store_listing',
          ),
          isFalse,
          reason: 'a stale editor must conflict, not silently refresh',
        );
      },
    );

    test('update refuses a record without an authoritative revision', () async {
      await expectLater(
        backend.saveListing(
          localListing(id: listingId, revision: 0),
          operationKey: 'key-rev',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.message,
            'message',
            contains('Refresh your Store'),
          ),
        ),
      );
      expect(transport.calls, isEmpty);
    });

    test('create refuses a listing without a catalogue category', () async {
      await expectLater(
        backend.saveListing(
          localListing(categoryId: null),
          operationKey: 'key-cat',
        ),
        throwsA(isA<StoreBackendException>()),
      );
      expect(transport.calls, isEmpty);
    });

    test('status and archive use the carried revision', () async {
      transport.handler = (call) =>
          data(listingJson(status: 'paused', revision: 5));
      await backend.setListingStatus(
        listingId,
        LocalListingStatus.paused,
        operationKey: 'status-key',
        expectedRevision: 4,
      );
      var input =
          transport.calls.last.params['p_input']! as Map<String, Object?>;
      expect(input['expected_revision'], 4);
      expect(input['publish'], false);

      await backend.archiveListing(
        listingId,
        operationKey: 'archive-key',
        expectedRevision: 5,
      );
      input = transport.calls.last.params['p_input']! as Map<String, Object?>;
      expect(transport.calls.last.params['p_operation'], 'store.archive');
      expect(input['expected_revision'], 5);
    });

    test('a network failure is ambiguous; a conflict is definitive', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
      await expectLater(
        backend.saveListing(localListing(), operationKey: 'key-a'),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isTrue,
          ),
        ),
      );

      transport.handler = (call) =>
          serverError('revision_conflict', code: 'P0001');
      await expectLater(
        backend.saveListing(
          localListing(id: listingId, revision: 2),
          operationKey: 'key-b',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isFalse,
          ),
        ),
      );
    });

    test('loadCategories returns retired entries for legacy display', () async {
      transport.handler = (call) => data(catalogueJson());
      final categories = await backend.loadCategories();
      expect(categories.single.id, categoryId);
      expect(categories.single.status, 'active');
      expect(categories.single.scope, 'product');
    });

    test('maps a plan limit to a user-safe definitive message', () async {
      transport.handler = (call) =>
          serverError('store_limit_exceeded', code: 'P0001');
      await expectLater(
        backend.saveListing(localListing(), operationKey: 'key-c'),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.message,
            'message',
            'Your plan Store limit was reached.',
          ),
        ),
      );
    });
  });
}

MarketplaceTransportResponse data(Object? value) =>
    MarketplaceTransportData(value);

MarketplaceTransportResponse serverError(String message, {String? code}) =>
    MarketplaceTransportError(
      kind: MarketplaceTransportErrorKind.server,
      message: message,
      code: code,
    );
