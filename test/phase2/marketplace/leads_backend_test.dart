// Seller leads wiring tests: repository lifecycle and Phase 2 mapping.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_leads_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/requests.dart';

import 'support/marketplace_fakes.dart';

class FakeLeadsBackend implements MarketplaceLeadsBackend {
  Future<List<SellerLeadProjection>> Function()? onLoad;

  @override
  Future<List<SellerLeadProjection>> loadLeads() =>
      onLoad?.call() ?? Future.value(const []);
}

SellerLeadProjection lead({
  String id = '30000000-0000-4000-8000-000000000001',
  int revision = 1,
}) => SellerLeadProjection(
  requestId: id,
  kind: RequestKind.product,
  title: 'Synthetic request',
  description: 'Synthetic details',
  condition: ProductCondition.used,
  quantity: 1,
  buyerProfileId: buyerProfileId,
  buyerDisplayName: 'Buyer A',
  areaLabel: 'Yonkers, NY',
  requestRevision: revision,
);

void main() {
  group('LocalMarketplaceRepository leads', () {
    test('loads leads and clears loading', () async {
      final backend = FakeLeadsBackend()..onLoad = () async => [lead()];
      final repository = LocalMarketplaceRepository(leadsBackend: backend);
      final refresh = repository.refreshSellerLeads();
      expect(repository.sellerLeadsLoading, isTrue);
      await refresh;
      expect(repository.sellerLeadsLoading, isFalse);
      expect(repository.sellerLeads.single.title, 'Synthetic request');
      expect(repository.sellerLeadsError, isNull);
    });

    test('surfaces a safe error', () async {
      final backend = FakeLeadsBackend()
        ..onLoad = () async => throw const StoreBackendException(
          'Check your connection and try again.',
        );
      final repository = LocalMarketplaceRepository(leadsBackend: backend);
      await repository.refreshSellerLeads();
      expect(
        repository.sellerLeadsError,
        'Check your connection and try again.',
      );
      expect(repository.sellerLeads, isEmpty);
    });

    test('an older refresh cannot replace newer leads', () async {
      final gate = Completer<void>();
      var call = 0;
      final backend = FakeLeadsBackend();
      backend.onLoad = () async {
        call += 1;
        if (call == 1) {
          await gate.future;
          return [lead(id: '30000000-0000-4000-8000-00000000000a')];
        }
        return [lead(id: '30000000-0000-4000-8000-00000000000b')];
      };
      final repository = LocalMarketplaceRepository(leadsBackend: backend);
      final stale = repository.refreshSellerLeads();
      await repository.refreshSellerLeads();
      gate.complete();
      await stale;
      expect(
        repository.sellerLeads.single.requestId,
        '30000000-0000-4000-8000-00000000000b',
      );
    });

    test('disposing during a load applies nothing', () async {
      final gate = Completer<void>();
      final backend = FakeLeadsBackend();
      backend.onLoad = () async {
        await gate.future;
        return [lead()];
      };
      final repository = LocalMarketplaceRepository(leadsBackend: backend);
      final pending = repository.refreshSellerLeads();
      repository.dispose();
      gate.complete();
      await pending;
      expect(repository.sellerLeads, isEmpty);
    });
  });

  group('Phase2MarketplaceLeadsBackend', () {
    test('loads projections through the adapter', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = MarketplaceDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2MarketplaceLeadsBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
      transport.handler = (call) =>
          MarketplaceTransportData(pageJson([leadJson()]));
      final leads = await backend.loadLeads();
      expect(leads.single.requestId, requestId);
      expect(leads.single.buyerDisplayName, 'Buyer A');
      expect(leads.single.requestRevision, 1);
      expect(transport.calls.single.function, 'marketplace_seller_leads');
    });

    test('maps a permission failure to a safe message', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = MarketplaceDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2MarketplaceLeadsBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
        message: 'role_not_active',
        code: '42501',
      );
      await expectLater(
        backend.loadLeads(),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.message,
            'message',
            'Your seller access is not active.',
          ),
        ),
      );
    });
  });
}
