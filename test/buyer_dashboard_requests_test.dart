// Buyer dashboard request list tests: real request rows, states and mapping.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

import 'test_fonts.dart';

MarketplaceRequest _request({
  String id = '30000000-0000-4000-8000-000000000001',
  String title = 'iPad Air, 5th gen or newer',
  int minimum = 35000,
  int maximum = 48000,
  RequestStatus status = RequestStatus.active,
}) => MarketplaceRequest(
  id: id,
  buyerProfileId: '10000000-0000-4000-8000-00000000000a',
  buyerUserId: 'user-a',
  draft: RequestDraft(
    kind: RequestKind.product,
    title: title,
    condition: ProductCondition.used,
    budget: MoneyRange(
      minimum: Money(minorUnits: minimum, currencyCode: 'USD'),
      maximum: Money(minorUnits: maximum, currencyCode: 'USD'),
    ),
  ),
  status: status,
  stamp: RecordStamp(
    revision: 1,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

ApprovedBuyerHomePage _page({
  List<BuyerRequestView>? realRequests,
  bool requestsLoading = false,
  String? requestsError,
  VoidCallback? onRefreshRequests,
  ValueChanged<BuyerRequestView>? onOpenRequest,
  ValueChanged<BuyerRequestView>? onOpenOffers,
  Future<Map<String, dynamic>> Function()? loadRealRewards,
  List<MeetingView>? realMeetings,
  ValueChanged<MeetingView>? onOpenMeeting,
  List<ApprovedActivityView>? realActivity,
  bool activityLoading = false,
  String? activityError,
  VoidCallback? onRefreshActivity,
  ValueChanged<ApprovedActivityView>? onOpenActivity,
  Future<void> Function()? onRefresh,
}) => ApprovedBuyerHomePage(
  onOpenActivity: onOpenActivity,
  onRefresh: onRefresh,
  name: 'Maya Chen',
  requestTitle: 'Prototype request',
  requestPosted: false,
  onCreate: () {},
  onRequestDetails: () {},
  onOffers: () {},
  onRecentActivity: () {},
  onWallet: () {},
  realRequests: realRequests,
  requestsLoading: requestsLoading,
  requestsError: requestsError,
  onRefreshRequests: onRefreshRequests,
  onOpenRequest: onOpenRequest,
  onOpenOffers: onOpenOffers,
  loadRealRewards: loadRealRewards,
  realMeetings: realMeetings,
  onOpenMeeting: onOpenMeeting,
  realActivity: realActivity,
  activityLoading: activityLoading,
  activityError: activityError,
  onRefreshActivity: onRefreshActivity,
);

void main() {
  testWidgets('home shows newest four and View all reveals older requests', (
    tester,
  ) async {
    final rows = List.generate(
      5,
      (i) => BuyerRequestView(
        requestId: 'request-$i',
        revision: 1,
        title: 'Request $i',
        budgetLabel: 'Budget',
        statusLabel: 'Active request',
        createdAt: DateTime.utc(2026, 10, i + 1),
      ),
    );
    await _pump(tester, _page(realRequests: rows));
    expect(find.text('Request 0'), findsNothing);
    expect(find.text('Request 4'), findsOneWidget);
    await tester.ensureVisible(find.text('View all').first);
    await tester.tap(find.text('View all').first);
    await tester.pumpAndSettle();
    expect(find.text('Request 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  setUpAll(loadHocalistTestFonts);

  testWidgets('real dashboard uses ledger rewards and hides prototype payout', (
    tester,
  ) async {
    await _pump(
      tester,
      _page(
        realRequests: const [],
        loadRealRewards: () async => {
          'currency': 'USD',
          'earned_minor': 150,
          'items': [
            {'amount_minor': 150, 'status': 'earned'},
            {'amount_minor': 30, 'status': 'held'},
          ],
        },
      ),
    );
    expect(find.text(r'$1.50'), findsOneWidget);
    expect(find.text(r'$0.30'), findsOneWidget);
    expect(find.text(r'$128.45'), findsNothing);
    expect(find.text('Pay date: May 20, 2025'), findsNothing);
    expect(find.textContaining('next payout'), findsNothing);
  });

  testWidgets('real dashboard does not invent rewards on ledger failure', (
    tester,
  ) async {
    await _pump(
      tester,
      _page(
        realRequests: const [],
        loadRealRewards: () async => throw StateError('offline'),
      ),
    );
    expect(find.text(r'$128.45'), findsNothing);
    expect(find.text(r'$24.80'), findsNothing);
    expect(find.text('Rewards unavailable'), findsOneWidget);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('real reward cards fit $width at text scale $scale', (
        tester,
      ) async {
        await _pump(
          tester,
          _page(
            realRequests: const [],
            loadRealRewards: () async => {
              'currency': 'USD',
              'earned_minor': 150,
              'items': const [],
            },
          ),
          width: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('real requests replace the prototype request card', (
    tester,
  ) async {
    await _pump(
      tester,
      _page(
        realRequests: [
          BuyerRequestView.fromRequest(_request(title: 'Gaming laptop')),
        ],
      ),
    );
    expect(find.text('Gaming laptop'), findsOneWidget);
    expect(find.text('Prototype request'), findsNothing);
    expect(find.text('Product PIN: 12345'), findsNothing);
    expect(find.textContaining(r'$350 - $480'), findsOneWidget);
  });

  testWidgets('real buyer dashboard keeps the banner without referral claim', (
    tester,
  ) async {
    await _pump(tester, _page(realRequests: const [], realMeetings: const []));
    expect(find.byKey(const Key('buyerMeetingsEmpty')), findsOneWidget);
    expect(find.text('Northside Tech'), findsNothing);
    expect(find.textContaining('Refer friends'), findsNothing);
    expect(
      find.byKey(const ValueKey('approved-keep-earning-banner')),
      findsOneWidget,
    );
    expect(find.text('Keep earning rewards'), findsOneWidget);
  });

  testWidgets('real dashboard requests Offers carries the tapped identity', (
    tester,
  ) async {
    BuyerRequestView? opened;
    await _pump(
      tester,
      _page(
        realRequests: [
          BuyerRequestView.fromRequest(_request(title: 'Gaming laptop')),
        ],
        onOpenOffers: (view) => opened = view,
      ),
    );
    await tester.ensureVisible(find.text('View offers  ›').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View offers  ›').first);
    await tester.pumpAndSettle();
    expect(opened?.title, 'Gaming laptop');
  });

  testWidgets('home recent activity shows designed empty and real states', (
    tester,
  ) async {
    await _pump(tester, _page(realRequests: const [], realActivity: const []));
    expect(find.byKey(const Key('buyerActivityEmpty')), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('No recent activity yet'), findsOneWidget);

    ApprovedActivityView? openedActivity;
    await _pump(
      tester,
      _page(
        onOpenActivity: (item) => openedActivity = item,
        realRequests: const [],
        realActivity: [
          ApprovedActivityView.fromNotification(
            NotificationInboxItem(
              id: 'n-1',
              kind: 'new_offer',
              title: 'A seller sent you an offer',
              activitySummary: 'Oct 20 · 4:00 PM America/Chicago',
              createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
            ),
          ),
        ],
      ),
    );
    expect(find.text('A seller sent you an offer'), findsOneWidget);
    await tester.ensureVisible(find.text('A seller sent you an offer'));
    await tester.tap(find.text('A seller sent you an offer'));
    expect(openedActivity?.id, 'n-1');
    expect(find.text('Oct 20 · 4:00 PM America/Chicago'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('buyerActivityUnreadDot')),
      findsOneWidget,
    );

    await _pump(
      tester,
      _page(
        realRequests: const [],
        realActivity: const [],
        activityError: 'Could not load activity.',
        onRefreshActivity: () {},
      ),
    );
    expect(find.byKey(const Key('buyerActivityError')), findsOneWidget);
  });

  testWidgets('real meeting opens the authoritative meeting id', (
    tester,
  ) async {
    final meeting = MeetingView(
      meetingId: 'meeting-42',
      meetingExpiresAt: DateTime.now().add(const Duration(days: 1)),
      conversationId: 'conversation-42',
      requestId: 'request-42',
      offerId: 'offer-42',
      buyerUserId: 'buyer-42',
      sellerUserId: 'seller-42',
      status: 'accepted',
      revision: 1,
      offerSummary: const MeetingOfferSummary(
        title: 'Real item',
        priceMinor: 12000,
        currencyCode: 'USD',
        revisionId: 'revision-42',
      ),
      revisions: const [],
    );
    MeetingView? opened;
    await _pump(
      tester,
      _page(
        realRequests: const [],
        realMeetings: [meeting],
        onOpenMeeting: (value) => opened = value,
      ),
    );
    final row = find.byKey(const ValueKey('buyerMeeting-meeting-42'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(find.text('Real item'), findsOneWidget);
    await tester.tap(row);
    expect(opened?.meetingId, 'meeting-42');
  });

  testWidgets('real request rows open by identity', (tester) async {
    BuyerRequestView? opened;
    await _pump(
      tester,
      _page(
        realRequests: [
          BuyerRequestView.fromRequest(
            _request(id: '30000000-0000-4000-8000-000000000042'),
          ),
        ],
        onOpenRequest: (view) => opened = view,
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('approved-active-request-card')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('approved-active-request-card')).first,
    );
    await tester.pumpAndSettle();
    expect(opened?.requestId, '30000000-0000-4000-8000-000000000042');
  });

  testWidgets('dashboard shows loading, error and empty request states', (
    tester,
  ) async {
    await _pump(tester, _page(realRequests: const [], requestsLoading: true));
    expect(find.byKey(const Key('buyerRequestsLoading')), findsOneWidget);

    await _pump(
      tester,
      _page(
        realRequests: const [],
        requestsError: 'Could not load your requests.',
        onRefreshRequests: () {},
      ),
    );
    expect(find.byKey(const Key('buyerRequestsError')), findsOneWidget);
    expect(find.byKey(const Key('buyerRequestsRetry')), findsOneWidget);

    await _pump(tester, _page(realRequests: const []));
    expect(find.byKey(const Key('buyerRequestsEmpty')), findsOneWidget);
  });

  testWidgets('request view maps status and budget', (tester) async {
    final view = BuyerRequestView.fromRequest(
      _request(status: RequestStatus.closed, minimum: 12000, maximum: 12000),
    );
    expect(view.statusLabel, 'Closed request');
    expect(view.canViewOffers, false);
    expect(view.budgetLabel, r'$120 - $120');
    expect(view.revision, 1);
  });
}
