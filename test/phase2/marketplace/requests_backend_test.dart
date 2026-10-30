// Buyer request backend tests: complete draft mapping, operation keys,
// uncertain outcomes, repository cache and category loading. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_requests_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/requests.dart';

import 'support/marketplace_fakes.dart';

class FakeRequestsBackend implements MarketplaceRequestsBackend {
  Future<List<MarketplaceRequest>> Function()? onLoad;
  Future<List<CatalogueCategoryOption>> Function()? onCategories;
  Future<MarketplaceRequest> Function(RequestDraft draft, String key)? onCreate;
  Future<MarketplaceRequest> Function(
    String requestId,
    int expectedRevision,
    RequestDraft draft,
    String key,
  )?
  onUpdate;
  Future<MarketplaceRequest> Function(
    String requestId,
    int revision,
    String key,
  )?
  onClose;
  final List<String> createKeys = <String>[];
  final List<RequestDraft> createdDrafts = <RequestDraft>[];

  @override
  Future<List<CatalogueCategoryOption>> loadCategories() =>
      onCategories?.call() ?? Future.value(const <CatalogueCategoryOption>[]);

  @override
  Future<List<MarketplaceRequest>> loadBuyerRequests() =>
      onLoad?.call() ?? Future.value(const <MarketplaceRequest>[]);

  @override
  Future<MarketplaceRequest> createRequest({
    required RequestDraft draft,
    required String operationKey,
  }) {
    createKeys.add(operationKey);
    createdDrafts.add(draft);
    return onCreate?.call(draft, operationKey) ?? Future.value(request());
  }

  @override
  Future<MarketplaceRequest> updateRequest({
    required String requestId,
    required int expectedRevision,
    required RequestDraft draft,
    required String operationKey,
  }) {
    return onUpdate?.call(requestId, expectedRevision, draft, operationKey) ??
        Future.value(request());
  }

  @override
  Future<MarketplaceRequest> closeRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  }) {
    return onClose?.call(requestId, expectedRevision, operationKey) ??
        Future.value(request(status: RequestStatus.closed));
  }
}

MarketplaceRequest request({RequestStatus status = RequestStatus.active}) {
  return MarketplaceRequest(
    id: requestId,
    buyerProfileId: buyerProfileId,
    buyerUserId: buyerId,
    draft: RequestDraft(
      kind: RequestKind.product,
      title: 'iPad Air, 5th gen or newer',
      description: 'Needs to be in good condition.',
      condition: ProductCondition.used,
      quantity: 1,
      budget: MoneyRange(
        minimum: Money(minorUnits: 35000, currencyCode: 'USD'),
        maximum: Money(minorUnits: 48000, currencyCode: 'USD'),
      ),
      acceptsHigherOffers: false,
      categoryId: categoryId,
    ),
    status: status,
    stamp: RecordStamp(
      revision: 1,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    ),
  );
}

RequestDraft draft({int minimum = 35000, int maximum = 48000}) => RequestDraft(
  kind: RequestKind.product,
  title: 'iPad Air, 5th gen or newer',
  description: 'Needs to be in good condition.',
  condition: ProductCondition.used,
  quantity: 1,
  budget: MoneyRange(
    minimum: Money(minorUnits: minimum, currencyCode: 'USD'),
    maximum: Money(minorUnits: maximum, currencyCode: 'USD'),
  ),
  acceptsHigherOffers: false,
  categoryId: categoryId,
);

void main() {
  group('LocalMarketplaceRepository requests', () {
    test('loads buyer requests and surfaces a safe error', () async {
      final backend = FakeRequestsBackend()..onLoad = () async => [request()];
      final repository = LocalMarketplaceRepository(requestsBackend: backend);
      await repository.refreshBuyerRequests();
      expect(repository.buyerRequests, hasLength(1));
      expect(repository.buyerRequestsError, isNull);
      expect(repository.buyerRequestsLoading, isFalse);

      backend.onLoad = () async =>
          throw const StoreBackendException('Check your connection.');
      await repository.refreshBuyerRequests();
      expect(repository.buyerRequestsError, 'Check your connection.');
      expect(repository.buyerRequests, hasLength(1));
    });

    test('loads catalogue categories with their scope', () async {
      final backend = FakeRequestsBackend()
        ..onCategories = () async => const [
          CatalogueCategoryOption(
            id: categoryId,
            label: 'Electronics',
            scope: 'product',
            status: 'active',
          ),
          CatalogueCategoryOption(
            id: '20000000-0000-4000-8000-000000000002',
            label: 'Cleaning',
            scope: 'service',
            status: 'active',
          ),
        ];
      final repository = LocalMarketplaceRepository(requestsBackend: backend);
      await repository.refreshRequestCategories();
      expect(repository.requestCategories, hasLength(2));
      expect(repository.requestCategories.first.supportsProduct, isTrue);
      expect(repository.requestCategories.first.supportsService, isFalse);
      expect(repository.requestCategories.last.supportsService, isTrue);
      expect(repository.requestCategoriesLoading, isFalse);
    });

    test('create upserts the acknowledged request', () async {
      final backend = FakeRequestsBackend();
      final repository = LocalMarketplaceRepository(requestsBackend: backend);
      final result = await repository.createBuyerRequest(
        draft: draft(),
        operationKey: 'create-1',
      );
      expect(result.isSuccess, isTrue);
      expect(result.outcomeUncertain, isFalse);
      expect(repository.buyerRequests.single.id, requestId);
      expect(backend.createKeys, ['create-1']);
    });

    test(
      'create reports an uncertain outcome without losing the key',
      () async {
        final backend = FakeRequestsBackend()
          ..onCreate = (_, _) async => throw const StoreBackendException(
            'The request could not be confirmed. Retry to check it safely.',
            ambiguous: true,
          );
        final repository = LocalMarketplaceRepository(requestsBackend: backend);
        final result = await repository.createBuyerRequest(
          draft: draft(),
          operationKey: 'create-uncertain',
        );
        expect(result.isSuccess, isFalse);
        expect(result.outcomeUncertain, isTrue);
        expect(repository.buyerRequests, isEmpty);
      },
    );

    test('create is unavailable without a backend', () async {
      final repository = LocalMarketplaceRepository();
      await expectLater(
        repository.createBuyerRequest(draft: draft(), operationKey: 'k'),
        throwsA(isA<StoreBackendException>()),
      );
    });
  });

  group('Phase2MarketplaceRequestsBackend', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MarketplaceDataAdapter adapter;
    late Phase2MarketplaceRequestsBackend backend;

    setUp(() {
      session = FakeMarketplaceSession(buyerId);
      transport = FakeMarketplaceTransport();
      adapter = MarketplaceDataAdapter(transport: transport, session: session);
      backend = Phase2MarketplaceRequestsBackend(
        adapter: adapter,
        buyerUserId: buyerId,
      );
    });

    test('create sends every draft field with the operation key', () async {
      transport.handler = (call) => MarketplaceTransportData(requestJson());
      final created = await backend.createRequest(
        draft: draft(),
        operationKey: 'request-key',
      );
      expect(created.id, requestId);
      final call = transport.calls.single;
      expect(call.function, 'marketplace_command');
      expect(call.params['p_operation'], 'request.create');
      expect(call.params['p_key'], 'request-key');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['kind'], 'product');
      expect(input['title'], 'iPad Air, 5th gen or newer');
      expect(input['description'], 'Needs to be in good condition.');
      expect(input['condition'], 'used');
      expect(input['quantity'], 1);
      expect(input['budget_minimum_minor'], 35000);
      expect(input['budget_maximum_minor'], 48000);
      expect(input['category_id'], categoryId);
      expect(input['use_home_address'], true);
    });

    test(
      'selected request timezone is sent and restored from the owner read',
      () async {
        transport.handler = (call) {
          final json = requestJson();
          (json['location'] as Map)['timezone_id'] = 'America/Chicago';
          return MarketplaceTransportData(json);
        };
        final result = await backend.createRequest(
          draft: draft().copyWith(
            location: RequestLocation.custom(
              address: PostalAddress(city: 'Chicago'),
              timezoneId: 'America/Chicago',
            ),
          ),
          operationKey: 'request-zone',
        );
        final input = transport.calls.single.params['p_input'] as Map;
        expect(input['location_timezone'], 'America/Chicago');
        expect(result.draft.location.timezoneId, 'America/Chicago');
      },
    );

    test('update carries the expected revision', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(requestJson(revision: 4));
      await backend.updateRequest(
        requestId: requestId,
        expectedRevision: 3,
        draft: draft(),
        operationKey: 'update-key',
      );
      final call = transport.calls.single;
      expect(call.params['p_operation'], 'request.update');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['request_id'], requestId);
      expect(input['expected_revision'], 3);
      expect(input['category_id'], categoryId);
    });

    test('close uses request.close with the expected revision', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(requestJson(status: 'closed'));
      final closed = await backend.closeRequest(
        requestId: requestId,
        expectedRevision: 2,
        operationKey: 'close-key',
      );
      expect(closed.status, RequestStatus.closed);
      final call = transport.calls.single;
      expect(call.params['p_operation'], 'request.close');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['expected_revision'], 2);
    });

    test('loads paged buyer requests', () async {
      var pages = 0;
      transport.handler = (call) {
        pages += 1;
        return MarketplaceTransportData(
          pageJson([requestJson()], cursor: pages == 1 ? 'next-page' : null),
        );
      };
      final loaded = await backend.loadBuyerRequests();
      expect(loaded, hasLength(2));
      expect(transport.calls, hasLength(2));
      expect(transport.calls.first.function, 'marketplace_my_requests');
      expect(transport.calls.first.params['p_limit'], 50);
      expect(transport.calls.last.params['p_cursor'], 'next-page');
    });

    test('maps a network failure to an ambiguous outcome', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
      await expectLater(
        backend.createRequest(draft: draft(), operationKey: 'k'),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isTrue,
          ),
        ),
      );
    });
    test('active request cap keeps the actionable server-mapped explanation', () async {
      transport.handler = (_) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
        message: 'active_request_limit_reached:4', code: 'P0001',
      );
      await expectLater(backend.createRequest(draft: draft(), operationKey: 'cap-test'),
        throwsA(isA<StoreBackendException>()
          .having((e) => e.message, 'message', contains('4 active requests'))
          .having((e) => e.message, 'action', contains('Close a request'))
          .having((e) => e.ambiguous, 'ambiguous', isFalse)));
    });
  });
}
