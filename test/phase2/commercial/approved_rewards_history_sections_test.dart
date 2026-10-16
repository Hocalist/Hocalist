// Approved rewards/deal-history sections in real mode: the approved layout
// must render from authoritative reads, and missing capability must show a
// designed state instead of prototype or fabricated values.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/withdrawal_backend.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

import '../../test_fonts.dart';
import 'support/commercial_payloads.dart';

RewardWalletView _wallet({
  bool policyConfigured = true,
  bool withdrawalConfigured = true,
  bool providerConfigured = false,
  int earned = 7000,
  int pending = 1500,
  int available = 5000,
  List<Map<String, Object?>>? items,
}) => RewardWalletView.fromJson(
  rewardWalletJson(
    policyConfigured: policyConfigured,
    withdrawalConfigured: withdrawalConfigured,
    providerConfigured: providerConfigured,
    earned: earned,
    pending: pending,
    paid: 0,
    processing: 0,
    items:
        items ??
        [
          {
            'id': 'rw-1',
            'amount_minor': 150,
            'created_at': '2026-09-23T12:00:00Z',
            'status': 'earned',
            'hold_minor': 0,
            'reversed_minor': 0,
            'shortfall_minor': 0,
            'item_title': 'Sold laptop',
          },
          {
            'id': 'rw-2',
            'amount_minor': 100,
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

WithdrawalStatusView _withdrawals({
  List<WithdrawalRequestView> requests = const [],
}) => WithdrawalStatusView(
  minimumMinor: 2000,
  feeMinor: 250,
  earnedMinor: 7000,
  processingMinor: 1000,
  availableMinor: 5000,
  emailVerified: true,
  phoneVerified: true,
  requests: requests,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Nunito'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1200),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets('approved reward sections render from the authoritative wallet', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(
        load: () async => _wallet(),
        loadWithdrawals: () async => _withdrawals(
          requests: [
            WithdrawalRequestView(
              id: 'w-1',
              amountMinor: 3000,
              feeMinor: 250,
              netMinor: 2750,
              status: 'processing',
              createdAt: DateTime.utc(2026, 9, 20),
            ),
          ],
        ),
        onWithdraw: () {},
        onDealHistory: () {},
      ),
    );

    expect(find.byKey(const ValueKey('approved-rewards-hero')), findsOneWidget);
    expect(find.text('Total rewards earned'), findsOneWidget);
    expect(find.text('\$70.00'), findsOneWidget);
    expect(find.text('\$15.00'), findsWidgets);
    expect(
      find.byKey(const ValueKey('approved-rewards-next-payout-progress')),
      findsOneWidget,
    );
    expect(find.text('\$70.00 of \$20.00 ready'), findsOneWidget);
    expect(find.text('Sold laptop'), findsOneWidget);
    expect(find.text('Sold camera'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-payout-destination')),
      findsOneWidget,
    );
    expect(find.textContaining('Processing • funds reserved'), findsOneWidget);
    // Approved prototype values must never leak into real mode.
    expect(find.textContaining('128.45'), findsNothing);
    expect(find.textContaining('42 completed'), findsNothing);
    expect(find.textContaining('15230'), findsNothing);
  });

  testWidgets('missing reward policy and withdrawal terms stay designed', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(
        load: () async => _wallet(
          policyConfigured: false,
          withdrawalConfigured: false,
          earned: 0,
          pending: 0,
          available: 0,
          items: const [],
        ),
        onWithdraw: () {},
        onDealHistory: () {},
      ),
    );

    expect(find.text('—'), findsWidgets);
    expect(find.text('Policy not configured'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-next-payout-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-history-unavailable')),
      findsOneWidget,
    );
    expect(find.text('No earned rewards yet.'), findsOneWidget);
    expect(find.textContaining('\$0.15'), findsNothing);
    expect(find.textContaining('\$0.30'), findsNothing);
  });

  testWidgets('a failed reward read is honest and retryable', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(
        load: () async {
          calls++;
          throw StateError('ledger down');
        },
        onWithdraw: () {},
        onDealHistory: () {},
      ),
    );

    expect(
      find.byKey(const ValueKey('approved-rewards-error')),
      findsOneWidget,
    );
    expect(find.textContaining('\$'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('a failed reward read keeps every approved section visible', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(
        load: () async => throw StateError('ledger down'),
        onWithdraw: () {},
        onDealHistory: () {},
      ),
    );

    // Every approved section stays on the page with a designed state.
    expect(find.byKey(const ValueKey('approved-rewards-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-until-payout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-next-payout-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Reward activity'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-activity-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-payout-destination')),
      findsOneWidget,
    );
    expect(find.text('Payout history'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-history-unavailable')),
      findsOneWidget,
    );
    // One retry action only, and no fabricated or prototype amount.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('\$'), findsNothing);
    expect(find.textContaining('128.45'), findsNothing);
  });

  testWidgets('wallet loading keeps every approved section visible', (
    tester,
  ) async {
    final pending = Completer<RewardWalletView>();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Nunito'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 1400)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ApprovedBuyerRewardsRealSections(
                  load: () => pending.future,
                  onWithdraw: () {},
                  onDealHistory: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The loading strips animate indefinitely; inspect without settling.
    await tester.pump();

    expect(
      find.byKey(const ValueKey('approved-rewards-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-until-payout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-next-payout-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-activity-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-payout-destination')),
      findsOneWidget,
    );
    expect(find.text('Payout history'), findsOneWidget);
    expect(find.textContaining('\$'), findsNothing);

    pending.complete(_wallet());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('approved-rewards-earned')),
      findsOneWidget,
    );
  });

  testWidgets('a missing wallet keeps every approved section visible', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(onWithdraw: () {}, onDealHistory: () {}),
    );

    expect(find.byKey(const ValueKey('approved-rewards-hero')), findsOneWidget);
    expect(find.text('Rewards are not available yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-rewards-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-until-payout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-next-payout-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-activity-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-payout-destination')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-rewards-history-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('\$'), findsNothing);
  });

  testWidgets('payout history loads independently of the rewards wallet', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerRewardsRealSections(
        loadWithdrawals: () async => _withdrawals(
          requests: [
            WithdrawalRequestView(
              id: 'w-1',
              amountMinor: 3000,
              feeMinor: 250,
              netMinor: 2750,
              status: 'processing',
              createdAt: DateTime.utc(2026, 9, 20),
            ),
          ],
        ),
        onWithdraw: () {},
        onDealHistory: () {},
      ),
    );

    // The hero stays in its designed unavailable state, while the
    // authoritative payout history renders its real row.
    expect(find.text('Rewards are not available yet.'), findsOneWidget);
    expect(find.textContaining('Processing • funds reserved'), findsOneWidget);
    expect(find.textContaining('\$'), findsWidgets);
  });

  testWidgets('approved history sections render authoritative records', (
    tester,
  ) async {
    SaleDetailView? reviewed;
    await _pump(
      tester,
      ApprovedBuyerDealHistoryRealSections(
        load: ({DateTime? beforeTime, String? beforeId}) async => [
          SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson()),
          SaleHistoryEntryView.fromJson(saleHistorySaleJson()),
        ],
        loadDetail: (id) async => SaleDetailView.fromJson(
          saleDetailJson(id: id, side: id == 'so-2' ? 'purchase' : 'sale'),
        ),
        onSupport: () {},
        onReview: (detail) => reviewed = detail,
      ),
    );

    // Counts have no authoritative backend field yet: the approved metric
    // tiles show the designed unavailable value plus the honest note.
    expect(find.text('—'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('approved-history-counts-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Completed purchases'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-deal-history-filter-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-deal-history-record-so-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-deal-history-record-so-1')),
      findsOneWidget,
    );
    expect(find.text('Sold camera'), findsOneWidget);
    expect(find.text('Sold laptop'), findsOneWidget);
    // Approved prototype records must never leak into real mode.
    expect(find.textContaining('Northside Tech'), findsNothing);
    expect(find.textContaining('Samsung 65-inch'), findsNothing);
    expect(find.textContaining('MacBook Air'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('approved-deal-history-record-so-2')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('America/New_York'), findsOneWidget);
    expect(find.text('Purchase confirmed'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.textContaining('15230'), findsNothing);
    final review = find.byKey(const ValueKey('approved-deal-history-review'));
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    expect(reviewed?.id, 'so-2');
    expect(reviewed?.requestId, isNotEmpty);
  });

  testWidgets('empty history and attention filter show designed states', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedBuyerDealHistoryRealSections(
        load: ({DateTime? beforeTime, String? beforeId}) async => const [],
        onSupport: () {},
      ),
    );
    expect(find.text('No confirmed purchases yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    await _pump(
      tester,
      ApprovedBuyerDealHistoryRealSections(
        load: ({DateTime? beforeTime, String? beforeId}) async => [
          SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson()),
        ],
        loadDetail: (id) async =>
            SaleDetailView.fromJson(saleDetailJson(id: id, side: 'purchase')),
        onSupport: () {},
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('approved-deal-history-filter-attention')),
    );
    await tester.pumpAndSettle();
    expect(find.text('No deals match this filter'), findsOneWidget);
  });

  testWidgets('a failed history read is honest', (tester) async {
    await _pump(
      tester,
      ApprovedBuyerDealHistoryRealSections(
        load: ({DateTime? beforeTime, String? beforeId}) async {
          throw StateError('history down');
        },
        onSupport: () {},
      ),
    );
    expect(
      find.byKey(const ValueKey('approved-history-error')),
      findsOneWidget,
    );
    expect(find.textContaining('Sold'), findsNothing);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('real sections fit $width at $scale', (tester) async {
        await _pump(
          tester,
          ApprovedBuyerRewardsRealSections(
            load: () async => _wallet(),
            loadWithdrawals: () async => _withdrawals(),
            onWithdraw: () {},
            onDealHistory: () {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          ApprovedBuyerDealHistoryRealSections(
            load: ({DateTime? beforeTime, String? beforeId}) async => [
              SaleHistoryEntryView.fromJson(saleHistoryPurchaseJson()),
            ],
            loadDetail: (id) async => SaleDetailView.fromJson(
              saleDetailJson(id: id, side: 'purchase'),
            ),
            onSupport: () {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
