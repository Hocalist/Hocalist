// Real-mode UI proof for the discovery completion surfaces: recommended
// leads, Account health and the configured review submission.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/reviews/review_backend.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/reviews.dart';
import 'package:hocalist/features/approved/buyer_bottom_navigation.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/seller/approved_seller_home_page.dart';

import '../marketplace/support/marketplace_fakes.dart';
import '../commercial/support/commercial_payloads.dart';

SellerLeadProjection recommendedLead({
  String title = 'Used laptop',
  int? matchPercent = 80,
  double? distanceMiles = 3.4,
}) => SellerLeadProjection(
  requestId: requestId,
  kind: RequestKind.product,
  title: title,
  description: 'A working laptop',
  condition: ProductCondition.used,
  quantity: 1,
  budget: MoneyRange(
    minimum: Money(minorUnits: 30000, currencyCode: 'USD'),
    maximum: Money(minorUnits: 50000, currencyCode: 'USD'),
  ),
  buyerProfileId: buyerProfileId,
  buyerDisplayName: 'Buyer A',
  areaLabel: 'Yonkers, NY',
  distanceMiles: distanceMiles,
  matchPercent: matchPercent,
  requestRevision: 1,
);

class FakeReviewBackend implements ReviewBackend {
  final List<SubmitReviewCommand> submissions = [];
  final List<UpdateReviewCommand> updates = [];
  ReviewEligibilityView eligibility = const ReviewEligibilityView(
    requestId: requestId,
    eligible: true,
    reason: 'confirmed_purchase',
  );
  bool failNextWithAmbiguous = false;

  @override
  Future<ReviewEligibilityView> loadEligibility(String requestId) async =>
      eligibility;

  @override
  Future<OutcomeReview> submitReview(SubmitReviewCommand command) async {
    submissions.add(command);
    if (failNextWithAmbiguous) {
      failNextWithAmbiguous = false;
      throw const StoreBackendException(
        'The review could not be confirmed. Retry to check it safely.',
        ambiguous: true,
        code: 'review_submit',
      );
    }
    return OutcomeReview(
      id: '60000000-0000-4000-8000-000000000001',
      requestId: command.requestId,
      rating: command.rating,
      body: command.body,
      status: ReviewModerationState.published,
      revision: 1,
      createdAt: DateTime.utc(2026, 5, 1),
    );
  }

  @override
  Future<OutcomeReview> updateReview(UpdateReviewCommand command) async {
    updates.add(command);
    return OutcomeReview(
      id: command.reviewId,
      requestId: requestId,
      rating: command.rating,
      body: command.body,
      status: ReviewModerationState.published,
      revision: command.expectedRevision + 1,
      createdAt: DateTime.utc(2026, 5, 1),
    );
  }

  @override
  Future<PublicSellerReputation> loadReputation(String sellerProfileId) async =>
      PublicSellerReputation(
        sellerProfileId: sellerProfileId,
        ratingSum: 0,
        ratingCount: 0,
        completedDeals: 0,
      );
}

Future<void> pumpSellerHome(
  WidgetTester tester, {
  RecommendedLeadsView? recommended,
  SellerAccountHealthView? health,
  double width = 390,
  double scale = 1,
  ValueChanged<SellerHealthRestriction>? onAppeal,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ApprovedSellerHomePage(
          onLeads: () {},
          onBrowseRequests: () {},
          sellerName: 'Northside Tech',
          realLeads: const [],
          recommendedLeads: recommended,
          accountHealth: health,
          onAppealRestriction: onAppeal,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('real recommended leads replace the prototype cards', (
    tester,
  ) async {
    await pumpSellerHome(
      tester,
      recommended: RecommendedLeadsView(
        items: [recommendedLead()],
        basis: const RecommendedLeadsBasis(
          declaredCategoryLabels: ['Electronics'],
          areaLabel: 'Yonkers, NY',
          radiusMiles: 25,
        ),
        matchReasons: const [
          ['Matches your declared category'],
        ],
      ),
    );
    expect(find.text('Used laptop'), findsOneWidget);
    expect(find.text('80% Match'), findsOneWidget);
    expect(
      find.byKey(const Key('sellerHomeRecommendedBasis')),
      findsNothing,
    );
    expect(find.text('Pressure Washing'), findsNothing);
    expect(find.text('Gaming PC'), findsNothing);
  });

  testWidgets('recommended empty state keeps the section and explains the basis', (
    tester,
  ) async {
    await pumpSellerHome(
      tester,
      recommended: RecommendedLeadsView(
        items: const [],
        basis: const RecommendedLeadsBasis(areaLabel: 'Yonkers, NY'),
        unavailableReason: 'no_eligible_matches',
      ),
    );
    expect(find.text('Recommended leads for you'), findsOneWidget);
    expect(find.byKey(const Key('sellerHomeRecommendedEmpty')), findsOneWidget);
    expect(find.text('No matching requests right now'), findsOneWidget);
    expect(find.text('Recent leads'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets(
        'recommended, account health and sections stay visible at '
        '${width.toInt()}px/${scale}x',
        (tester) async {
          await pumpSellerHome(
            tester,
            width: width,
            scale: scale,
            recommended: RecommendedLeadsView(
              items: [recommendedLead(), recommendedLead(title: 'Second item')],
              basis: const RecommendedLeadsBasis(
                declaredCategoryLabels: ['Electronics'],
                areaLabel: 'Yonkers, NY',
                radiusMiles: 25,
              ),
              matchReasons: const [
                ['Matches your declared category'],
                [],
              ],
            ),
            health: const SellerAccountHealthView(
              emailVerified: true,
              phoneVerified: true,
              reviewStatus: 'approved',
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Recommended leads for you'), findsOneWidget);
          expect(find.text('Recent leads'), findsOneWidget);
          expect(find.byKey(const Key('sellerAccountHealth')), findsOneWidget);
        },
      );
    }
  }

  testWidgets('account health shows manual status and appeal action', (
    tester,
  ) async {
    SellerHealthRestriction? appealed;
    await pumpSellerHome(
      tester,
      health: const SellerAccountHealthView(
        emailVerified: true,
        phoneVerified: false,
        reviewStatus: 'pending',
        restrictions: [
          SellerHealthRestriction(
            id: 'restriction-1',
            scope: 'seller',
            reason: 'Repeated safety reports under review.',
          ),
        ],
      ),
      onAppeal: (restriction) => appealed = restriction,
    );
    expect(find.text('Restricted · review required'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerAccountHealth')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Repeated safety reports'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sellerAccountAppealrestriction-1')));
    await tester.pumpAndSettle();
    expect(appealed?.id, 'restriction-1');
  });

  testWidgets('configured review submits once and retries with the same key', (
    tester,
  ) async {
    final backend = FakeReviewBackend();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedBuyerReviewPage(
          onBack: () {},
          navigation: ApprovedBuyerNavigation(
            onHome: () {},
            onHocatrends: () {},
            onOffers: () {},
            onChats: () {},
            onMore: () {},
          ),
          onFinish: () {},
          backend: backend,
          requestId: requestId,
          sellerName: 'Seller B',
          purchase: SaleDetailView.fromJson(saleDetailJson(side: 'purchase')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Submit review'), findsOneWidget);
    expect(find.textContaining('iPad Air'), findsNothing);
    expect(find.textContaining('Northside Tech'), findsNothing);
    expect(find.text(r'$650'), findsNothing);
    expect(find.text('Sold laptop'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approved-submit-review')));
    await tester.pumpAndSettle();
    expect(backend.submissions, isEmpty);
    await tester.tap(find.byKey(const ValueKey('approved-review-star-3')));
    await tester.pumpAndSettle();

    backend.failNextWithAmbiguous = true;
    await tester.tap(find.byKey(const ValueKey('approved-submit-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry to check safely'), findsOneWidget);
    expect(backend.submissions, hasLength(1));
    final firstKey = backend.submissions.first.idempotencyKey;
    expect(backend.submissions.first.rating, 4);

    await tester.tap(find.byKey(const ValueKey('approved-submit-review')));
    await tester.pumpAndSettle();
    expect(backend.submissions, hasLength(2));
    expect(backend.submissions.last.idempotencyKey, firstKey);
    expect(
      find.text('Review saved. Thank you for helping future buyers.'),
      findsOneWidget,
    );
  });

  testWidgets('a non-confirmed purchase shows the honest eligibility state', (
    tester,
  ) async {
    final backend = FakeReviewBackend()
      ..eligibility = const ReviewEligibilityView(
        requestId: requestId,
        eligible: false,
        reason: 'not_confirmed',
      );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedBuyerReviewPage(
          onBack: () {},
          navigation: ApprovedBuyerNavigation(
            onHome: () {},
            onHocatrends: () {},
            onOffers: () {},
            onChats: () {},
            onMore: () {},
          ),
          onFinish: () {},
          backend: backend,
          requestId: requestId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('confirmed purchase'), findsWidgets);
    expect(find.byKey(const ValueKey('approved-submit-review')), findsNothing);
  });
}
