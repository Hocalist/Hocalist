import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/commercial_wallet_backend.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';

import 'support/commercial_payloads.dart';

void main() {
  test('seller homepage totals are authenticated and strictly decoded',()async {
    final backend=Phase2CommercialWalletBackend(identity:()=>'seller',rpc:(function,params)async{
      expect(function,'seller_home_summary');expect(params,isEmpty);
      return {'leads_targeted':147,'deals_closed':9,'month_start':'2026-10-01T00:00:00Z',
        'month_end':'2026-11-01T00:00:00Z','timezone':'UTC'};
    });
    final result=await backend.loadSellerHomeSummary();
    expect(result.leadsTargeted,147); expect(result.dealsClosed,9);
    expect(()=>SellerHomeSummaryView.fromJson({'leads_targeted':-1,'deals_closed':9,
      'month_start':'2026-10-01','month_end':'2026-11-01','timezone':'UTC'}),throwsA(isA<CommercialContractError>()));
  });
  group('CommercialWalletBackend', () {
    test('loads typed ledger reads and keeps the session fence', () async {
      String? user = 'user-1';
      final calls = <String>[];
      final backend = Phase2CommercialWalletBackend(
        identity: () => user,
        rpc: (function, params) async {
          calls.add(function);
          return switch (function) {
            'commercial_credit_wallet' => creditWalletJson(),
            'commercial_reward_wallet' => rewardWalletJson(),
            'commercial_sale_history' => {
              'items': [saleHistoryPurchaseJson(), saleHistorySaleJson()],
            },
            'commercial_sale_detail' => saleDetailJson(),
            _ => throw StateError('unexpected $function'),
          };
        },
      );
      final credit = await backend.loadCreditWallet();
      expect(credit.availableMinor, 5250);
      final rewards = await backend.loadRewardWallet();
      expect(rewards.availableMinor, 15);
      final history = await backend.loadSaleHistory();
      expect(history, hasLength(2));
      expect(history.first.side, SaleSide.purchase);
      final detail = await backend.loadSaleDetail('so-1');
      expect(detail.schedule.timezone, 'America/New_York');
      expect(calls, [
        'commercial_credit_wallet',
        'commercial_reward_wallet',
        'commercial_sale_history',
        'commercial_sale_detail',
      ]);
    });

    test('a session replacement during a call is refused', () async {
      String? user = 'user-1';
      final backend = Phase2CommercialWalletBackend(
        identity: () => user,
        rpc: (function, params) async {
          user = 'user-2';
          return creditWalletJson();
        },
      );
      await expectLater(
        backend.loadCreditWallet(),
        throwsA(
          isA<CommercialUnavailableException>().having(
            (error) => error.message,
            'message',
            contains('session changed'),
          ),
        ),
      );
    });

    test('a signed-out caller cannot read a ledger', () async {
      final backend = Phase2CommercialWalletBackend(
        identity: () => null,
        rpc: (function, params) async => creditWalletJson(),
      );
      await expectLater(
        backend.loadCreditWallet(),
        throwsA(isA<CommercialUnavailableException>()),
      );
    });

    test('an rpc access denial maps to a typed unavailable error', () async {
      final backend = Phase2CommercialWalletBackend(
        identity: () => 'user-1',
        rpc: (function, params) async => throw const CommercialRpcException(
          'wallet_access_denied',
          code: '42501',
        ),
      );
      await expectLater(
        backend.loadRewardWallet(),
        throwsA(
          isA<CommercialUnavailableException>().having(
            (error) => error.message,
            'message',
            contains('not available for your account'),
          ),
        ),
      );
    });

    test('a contract violation never becomes a fabricated amount', () async {
      final backend = Phase2CommercialWalletBackend(
        identity: () => 'user-1',
        rpc: (function, params) async => {
          ...creditWalletJson(),
          'available_minor': 1,
        },
      );
      await expectLater(
        backend.loadCreditWallet(),
        throwsA(
          isA<CommercialUnavailableException>().having(
            (error) => error.message,
            'message',
            contains('invalid'),
          ),
        ),
      );
    });

    test('history cursors are paired and detail ids are required', () async {
      final backend = Phase2CommercialWalletBackend(
        identity: () => 'user-1',
        rpc: (function, params) async => {'items': <Object?>[]},
      );
      await expectLater(
        backend.loadSaleHistory(beforeTime: DateTime.utc(2026)),
        throwsA(isA<CommercialUnavailableException>()),
      );
      await expectLater(
        backend.loadSaleHistory(beforeId: 'so-1'),
        throwsA(isA<CommercialUnavailableException>()),
      );
      await expectLater(
        backend.loadSaleDetail(''),
        throwsA(isA<CommercialUnavailableException>()),
      );
    });

    test('oversized history pages are refused', () async {
      final backend = Phase2CommercialWalletBackend(
        identity: () => 'user-1',
        rpc: (function, params) async => {
          'items': List.generate(26, (i) => saleHistoryPurchaseJson(id: 'so-$i')),
        },
      );
      await expectLater(
        backend.loadSaleHistory(),
        throwsA(isA<CommercialUnavailableException>()),
      );
    });

    test('the configured backend stays off until explicitly enabled', () {
      expect(kCommercialReadsEnabled, false);
      expect(createConfiguredCommercialWalletBackend(), isNull);
    });
  });
}
