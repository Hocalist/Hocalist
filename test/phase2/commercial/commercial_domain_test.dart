import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';

import 'support/commercial_payloads.dart';

void main() {
  group('credit wallet decoding', () {
    test('a valid server payload decodes with intact rates and quota', () {
      final view = CreditWalletView.fromJson(creditWalletJson());
      expect(view.currency, 'HC');
      expect(view.balanceMinor, 5470);
      expect(view.reservedMinor, 220);
      expect(view.availableMinor, 5250);
      expect(view.chargedMinor, 530);
      expect(view.weekly.used, 2);
      expect(view.weekly.limit, 10);
      expect(view.weekly.remaining, 8);
      expect(view.batches, hasLength(2));
      expect(view.batches.first.rateVersion, 'v40');
      expect(view.batches.first.winningTotalMinor, 375);
      expect(view.batches.first.availableMinor, 3625);
      expect(view.targets.single.status, CreditTargetStatus.initialCharged);
      expect(view.targets.single.requestTitle, 'Sold camera');
      expect(view.depositOptionsConfigured, false);
    });

    test('inconsistent availability is refused, not displayed', () {
      final mismatch = creditWalletJson();
      mismatch['available_minor'] = 999;
      expect(
        () => CreditWalletView.fromJson(mismatch),
        throwsA(isA<CommercialContractError>()),
      );
      final overReserved = creditWalletJson();
      overReserved['balance_minor'] = 100;
      overReserved['reserved_minor'] = 200;
      overReserved['available_minor'] = 0;
      expect(
        () => CreditWalletView.fromJson(overReserved),
        throwsA(isA<CommercialContractError>()),
      );
    });

    test('unknown currencies, statuses and batch shapes are refused', () {
      final wrongCurrency = creditWalletJson();
      wrongCurrency['currency'] = 'USD';
      expect(
        () => CreditWalletView.fromJson(wrongCurrency),
        throwsA(isA<CommercialContractError>()),
      );
      final badStatus = creditWalletJson(targets: [
        {...targetJson(), 'status': 'pending_review'},
      ]);
      expect(
        () => CreditWalletView.fromJson(badStatus),
        throwsA(isA<CommercialContractError>()),
      );
      final badBatch = creditWalletJson(batches: [
        {...batchJson(), 'winning_total_minor': 9999},
      ]);
      expect(
        () => CreditWalletView.fromJson(badBatch),
        throwsA(isA<CommercialContractError>()),
      );
    });
  });

  group('reward wallet decoding', () {
    test('earned, held, processing and available stay separate', () {
      final view = RewardWalletView.fromJson(
        rewardWalletJson(processing: 3000, paid: 1000),
      );
      expect(view.currency, 'USD');
      expect(view.earnedMinor, 15);
      expect(view.pendingMinor, 15);
      expect(view.processingMinor, 3000);
      expect(view.paidMinor, 1000);
      expect(view.withdrawal.configured, true);
      expect(view.withdrawal.minimumMinor, 2000);
      expect(view.withdrawal.contactVerified, true);
      expect(view.payout.providerNeutral, true);
      expect(view.payout.executionEnabled, false);
      expect(view.items, hasLength(2));
      expect(view.items.first.status, RewardItemStatus.earned);
      expect(view.items.last.status, RewardItemStatus.held);
    });

    test('a missing policy reports unavailable instead of a default rate', () {
      final view = RewardWalletView.fromJson(
        rewardWalletJson(
          policyConfigured: false,
          withdrawalConfigured: false,
        ),
      );
      expect(view.rewardPolicyConfigured, false);
      expect(view.normalMinor, isNull);
      expect(view.lateMinor, isNull);
      expect(view.withdrawal.configured, false);
      expect(view.withdrawal.minimumMinor, isNull);
    });

    test('impossible splits are refused', () {
      final overAvailable = rewardWalletJson(earned: 5, held: 5, pending: 5);
      overAvailable['available_minor'] = 6;
      expect(
        () => RewardWalletView.fromJson(overAvailable),
        throwsA(isA<CommercialContractError>()),
      );
      expect(
        () => RewardWalletView.fromJson(rewardWalletJson(earned: 10, held: 10, pending: 20)),
        throwsA(isA<CommercialContractError>()),
      );
    });
  });

  group('sale history and detail decoding', () {
    test('a confirmed purchase without a reward keeps its history row', () {
      final row = SaleHistoryEntryView.fromJson({
        ...saleHistoryPurchaseJson(),
        'reward': {
          'status': 'none',
          'amount_minor': null,
          'rule_version': null,
        },
      });
      expect(row.side, SaleSide.purchase);
      expect(row.reward?.status, 'none');
      expect(row.reward?.amountMinor, 0);
      for (final status in ['earned', 'held']) {
        expect(
          () => SaleRewardView.fromJson({
            'status': status,
            'amount_minor': null,
            'rule_version': 'test',
          }),
          throwsA(isA<CommercialContractError>()),
        );
      }
    });

    test('purchases and sales are distinct role-aware rows', () {
      final purchase = SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson());
      expect(purchase.side, SaleSide.purchase);
      expect(purchase.reward?.status, 'held');
      expect(purchase.fee, isNull);
      final sale = SaleHistoryEntryView.fromJson(saleHistorySaleJson());
      expect(sale.side, SaleSide.sale);
      expect(sale.fee?.chargedMinor, 375);
      expect(sale.reward, isNull);
    });

    test('an unknown side or non-offline item payment is refused', () {
      expect(
        () => SaleHistoryEntryView.fromJson(
          {...saleHistorySaleJson(), 'side': 'refund'},
        ),
        throwsA(isA<CommercialContractError>()),
      );
      expect(
        () => SaleDetailView.fromJson(
          {...saleDetailJson(), 'item_payment': 'card'},
        ),
        throwsA(isA<CommercialContractError>()),
      );
    });

    test('the detail keeps the zoned schedule and ledger facts', () {
      final detail = SaleDetailView.fromJson(saleDetailJson());
      expect(detail.itemPayment, 'offline');
      expect(detail.schedule.timezone, 'America/New_York');
      expect(detail.schedule.time, '18:30:00');
      expect(detail.schedule.meetingExpiresAt, isNotNull);
      expect(detail.fee?.rateVersion, 'v40');
    });
  });

  group('entitlement decoding', () {
    test('the settled threshold is reported while rules stay unconfigured', () {
      final view = SellerEntitlementView.fromJson(entitlementJson());
      expect(view.effectivePlan, PlanCode.free);
      expect(view.effectiveSource, EntitlementSource.free);
      expect(view.policy.earnedProThreshold, 7);
      expect(view.policy.calendarConfigured, false);
      expect(view.earned.configured, false);
      expect(view.earned.unavailableReason, 'calendar_unconfigured');
      expect(view.annualAvailable, false);
      expect(view.plans, hasLength(3));
      expect(view.plans[2].weeklyTargetLimit, 100);
    });

    test('a configured earned month reports progress and application', () {
      final view = SellerEntitlementView.fromJson(
        entitlementJson(
          effectivePlan: 'pro',
          effectiveSource: 'earned',
          calendarConfigured: true,
          earnedApplied: true,
          currentSales: 2,
        ),
      );
      expect(view.earned.configured, true);
      expect(view.earned.qualifyingWindow?.sales, 7);
      expect(view.earned.currentWindow?.sales, 2);
      expect(view.earned.applied, true);
    });

    test('a paid/earned overlap without an approved rule reports unconfigured',
        () {
      final view = SellerEntitlementView.fromJson(
        entitlementJson(
          effectivePlan: 'pro',
          effectiveSource: 'billing',
          calendarConfigured: true,
          billingPlan: 'pro',
          overlapUnconfigured: true,
        ),
      );
      expect(view.earned.plan, PlanCode.pro);
      expect(view.earned.applied, false);
      expect(view.earned.overlapUnconfigured, true);
    });

    test('impossible source and trial shapes are refused', () {
      expect(
        () => SellerEntitlementView.fromJson(
          entitlementJson(effectivePlan: 'free', effectiveSource: 'billing'),
        ),
        throwsA(isA<CommercialContractError>()),
      );
      final badTrial = entitlementJson();
      badTrial['trial'] = {'available': true, 'days': null};
      expect(
        () => SellerEntitlementView.fromJson(badTrial),
        throwsA(isA<CommercialContractError>()),
      );
      final missingWindow = entitlementJson(calendarConfigured: true);
      (missingWindow['verified'] as Map)['earned'] = {
        ...(missingWindow['verified'] as Map)['earned'] as Map<String, Object?>,
        'current_window': null,
      };
      expect(
        () => SellerEntitlementView.fromJson(missingWindow),
        throwsA(isA<CommercialContractError>()),
      );
    });

    test('the plan preview keeps an unconfigured downgrade explicit', () {
      final view = PlanPreviewView.fromJson(planPreviewJson());
      expect(view.planCode, PlanCode.free);
      expect(view.overLimit, true);
      expect(view.downgrade.policyConfigured, false);
      expect(view.downgrade.unavailableReason, 'downgrade_policy_unconfigured');
      expect(view.downgrade.wouldHideExisting, isNull);
      expect(view.downgrade.wouldBlockNewPublishes, isNull);
      expect(view.annualAmountMinor, isNull);
    });
  });

  group('reward wallet accounting agreement', () {
    test('held equals pending plus holds and matches per-item sums', () {
      final view = RewardWalletView.fromJson(
        rewardWalletJson(
          earned: 100,
          pending: 15,
          hold: 20,
          withdrawalHold: 5,
          reversed: 10,
          items: [
            {
              'id': 'a',
              'amount_minor': 40,
              'created_at': '2026-09-23T12:00:00Z',
              'status': 'held',
              'hold_minor': 20,
              'reversed_minor': 10,
              'shortfall_minor': 0,
              'item_title': 'Sold laptop',
            },
            {
              'id': 'b',
              'amount_minor': 15,
              'created_at': '2026-09-24T12:00:00Z',
              'status': 'held',
              'hold_minor': 0,
              'reversed_minor': 0,
              'shortfall_minor': 0,
              'item_title': 'Sold camera',
            },
          ],
        ),
      );
      expect(view.heldMinor, 40);
      expect(view.holdMinor, 20);
      expect(view.withdrawalHoldMinor, 5);
      expect(view.reversedMinor, 10);
      expect(view.availableMinor, 100 - 20 - 5 - 10);
      expect(view.items.first.holdMinor, 20);
      expect(view.items.first.reversedMinor, 10);
    });

    test('a top-level/per-item mismatch is refused', () {
      final mismatched = rewardWalletJson(hold: 5);
      (mismatched['items'] as List).first['hold_minor'] = 9;
      expect(
        () => RewardWalletView.fromJson(mismatched),
        throwsA(isA<CommercialContractError>()),
      );
      expect(
        () => RewardWalletView.fromJson(
          rewardWalletJson(earned: 5, pending: 0, reversed: 10),
        ),
        throwsA(isA<CommercialContractError>()),
      );
    });

    test('the dashboard projection is never more than what is withdrawable',
        () {
      final view = RewardWalletView.fromJson(
        rewardWalletJson(
          earned: 100,
          pending: 0,
          hold: 15,
          reversed: 10,
          processing: 20,
          paid: 30,
          items: [
            {
              'id': 'a',
              'amount_minor': 100,
              'created_at': '2026-09-23T12:00:00Z',
              'status': 'held',
              'hold_minor': 15,
              'reversed_minor': 10,
              'shortfall_minor': 0,
              'item_title': 'Sold laptop',
            },
          ],
        ),
      );
      final map = view.toDashboardMap();
      expect(map['earned_minor'], view.availableMinor);
      expect(map['earned_minor'], 25);
      expect(map['held_minor'], 15);
      expect(map['reversed_minor'], 10);
      expect((map['items'] as List).single['status'], 'held');
      expect((map['items'] as List).single['reversed_minor'], 10);
    });
    test('an unrecovered shortfall is audit-only and never deducted again', () {
      final view = RewardWalletView.fromJson(
        rewardWalletJson(
          earned: 7000,
          pending: 0,
          paid: 4000,
          shortfall: 4000,
          items: [
            {
              'id': 'paid-reward',
              'amount_minor': 4000,
              'created_at': '2026-09-23T12:00:00Z',
              'status': 'earned',
              'hold_minor': 0,
              'reversed_minor': 0,
              'shortfall_minor': 4000,
              'item_title': 'Paid reward',
            },
          ],
        ),
      );
      expect(view.shortfallMinor, 4000);
      expect(view.reversedMinor, 0);
      // The shortfall affects neither availability nor the held totals.
      expect(view.availableMinor, 3000);
      expect(view.heldMinor, 0);
      final map = view.toDashboardMap();
      expect(map['shortfall_minor'], 4000);
      expect(map['earned_minor'], 3000);
    });

    test('a per-item shortfall larger than the total is refused', () {
      final mismatched = rewardWalletJson(shortfall: 5);
      (mismatched['items'] as List).first['shortfall_minor'] = 9;
      expect(
        () => RewardWalletView.fromJson(mismatched),
        throwsA(isA<CommercialContractError>()),
      );
    });
  });
}
