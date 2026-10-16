// Entry-point example for the coordinator integration patch.
//
// Shows the intended composition: one configured backend supplies the typed
// loaders for the approved panels, and the entitlement backend reads the
// authoritative plan. Nothing here enables a flag or touches a live provider.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/commercial_wallet_backend.dart';
import 'package:hocalist/data/phase2/commercial/entitlement_backend.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/commercial/buyer_rewards_panel.dart';
import 'package:hocalist/features/commercial/credit_wallet_panel.dart';
import 'package:hocalist/features/commercial/sale_history_panel.dart';

import 'support/commercial_payloads.dart';

void main() {
  testWidgets('panels accept the production backend loaders without extras', (
    tester,
  ) async {
    final wallet = Phase2CommercialWalletBackend(
      identity: () => 'seller-1',
      rpc: (function, params) async => switch (function) {
        'commercial_credit_wallet' => creditWalletJson(),
        'commercial_reward_wallet' => rewardWalletJson(),
        'commercial_sale_history' => {
          'items': [saleHistoryPurchaseJson()],
        },
        'commercial_sale_detail' => saleDetailJson(side: 'purchase'),
        _ => throw StateError('unexpected $function'),
      },
    );
    final entitlement = Phase2EntitlementBackend(
      identity: () => 'seller-1',
      rpc: (function, params) async =>
          function == 'account_entitlement' ? entitlementJson() : planPreviewJson(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                CreditWalletPanel(load: wallet.loadCreditWallet),
                BuyerRewardsPanel(load: wallet.loadRewardWallet),
                SaleHistoryPanel(
                  load: wallet.loadSaleHistory,
                  loadDetail: wallet.loadSaleDetail,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('creditWalletPanel')), findsOneWidget);
    expect(find.byKey(const Key('buyerRewardsPanel')), findsOneWidget);
    expect(find.byKey(const Key('saleHistoryPanel')), findsOneWidget);

    final view = await entitlement.loadEntitlement();
    expect(view.effectiveSource, EntitlementSource.free);
    expect(view.policy.calendarConfigured, false);
    // Capability switches stay off until the coordinator flips them.
    expect(kCommercialReadsEnabled, false);
    expect(kEntitlementsEnabled, false);
  });
}
