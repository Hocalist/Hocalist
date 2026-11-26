// Buyer dashboard request list tests: real request rows, states and mapping.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/notifications.dart';
import 'package:hocalist/domain/phase2/requests.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/data/phase2/meetings/meeting_adapter.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

import 'test_fonts.dart';

MarketplaceRequest _request({
  String? purchaseOfferId,
  String id = '30000000-0000-4000-8000-000000000001',
  String title = 'iPad Air, 5th gen or newer',
  int minimum = 35000,
  int maximum = 48000,
  RequestStatus status = RequestStatus.active,
}) => MarketplaceRequest(
  purchaseOfferId: purchaseOfferId,
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
  ValueChanged<BuyerRequestView>? onCloseFromHome,
  ValueChanged<BuyerRequestView>? onOpenOffers,
  Future<Map<String, dynamic>> Function()? loadRealRewards,
  List<MeetingView>? realMeetings,
  ValueChanged<MeetingView>? onOpenMeeting,
  ValueChanged<MeetingView>? onOpenPinMeeting,
  ValueChanged<MeetingView>? onMeetingMessage,
  void Function(MeetingView, String, BuyerMeetupChange)? onManageMeetup,
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
  onCloseFromHome: onCloseFromHome,
  onOpenOffers: onOpenOffers,
  loadRealRewards: loadRealRewards,
  realMeetings: realMeetings,
  onOpenMeeting: onOpenMeeting,
  onOpenPinMeeting: onOpenPinMeeting,
  onMeetingMessage: onMeetingMessage,
  onManageTodayMeetup: onManageMeetup,
  realActivity: realActivity,
  activityLoading: activityLoading,
  activityError: activityError,
  onRefreshActivity: onRefreshActivity,
);

void main() {
  testWidgets(
    'Buyer Home upcoming card opens chat and manages the same meetup',
    (tester) async {
      final schedule = MeetingScheduleView(
        sequence: 1,
        date: LocalDate(year: 2098, month: 5, day: 10),
        startTime: LocalTime(hour: 13, minute: 30),
        timezoneId: 'UTC',
        offsetMinutes: 0,
        instant: DateTime.utc(2098, 5, 10, 13, 30),
        placeChoice: 'custom',
        placeLabel: 'City library',
        proposedByUserId: 'seller',
        status: 'accepted',
        createdAt: DateTime.utc(2026),
      );
      final meeting = MeetingView(
        meetingId: 'upcoming',
        conversationId: 'chat',
        requestId: 'request',
        offerId: 'offer',
        buyerUserId: 'buyer',
        sellerUserId: 'seller',
        status: 'accepted',
        revision: 1,
        meetingExpiresAt: DateTime.utc(2098, 5, 11),
        acceptedSchedule: schedule,
        revisions: [schedule],
        offerSummary: const MeetingOfferSummary(
          title: 'Camera Tripod',
          priceMinor: 3500,
          currencyCode: 'USD',
          revisionId: 'revision',
        ),
      );
      final messages = <MeetingView>[];
      final changes = <BuyerMeetupChange>[];
      await _pump(
        tester,
        _page(
          realRequests: const [],
          realMeetings: [meeting],
          onMeetingMessage: messages.add,
          onManageMeetup: (target, _, change) {
            expect(target, same(meeting));
            changes.add(change);
          },
        ),
        width: 320,
      );

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      final chat = find.byKey(const ValueKey('buyer-upcoming-meetup-message'));
      final manage = find.byKey(const ValueKey('buyer-upcoming-meetup-manage'));
      expect(
        tester.getTopLeft(chat).dy,
        lessThan(tester.getTopLeft(find.text('Camera Tripod')).dy),
      );
      expect(find.text('Maps'), findsNothing);
      expect(find.text('Call'), findsNothing);
      await tap(chat);
      expect(messages, [meeting]);
      for (final (label, action) in [
        ('Reschedule meetup', BuyerMeetupAction.reschedule),
        ('Cancel meetup', BuyerMeetupAction.cancel),
      ]) {
        await tap(manage);
        expect(find.text('Reschedule meetup'), findsOneWidget);
        expect(find.text('Cancel meetup'), findsOneWidget);
        await tap(find.text(label));
        await tap(find.text('Schedule changed'));
        await tap(find.text('Continue'));
        expect(changes.last.action, action);
        expect(changes.last.reason, 'schedule_changed');
        expect(find.text('Manage meetup'), findsNothing);
      }
      expect(changes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home orders requests by creation date regardless of deadline', (
    tester,
  ) async {
    final rows = List.generate(
      5,
      (i) => BuyerRequestView(
        requestId: 'expiry-$i', revision: 1, title: 'Expiry $i',
        budgetLabel: 'Budget', statusLabel: 'Active request',
        createdAt: DateTime.utc(2026, 10, i + 1),
        acceptanceExpiresAt: i == 4 ? null : DateTime.utc(2030, 1, i + 1),
      ),
    );
    rows.add(BuyerRequestView(
      requestId: 'closed', revision: 1, title: 'Closed history',
      budgetLabel: 'Budget', statusLabel: 'Closed request', isActive: false,
      createdAt: DateTime.utc(2031), acceptanceExpiresAt: DateTime.utc(2020),
    ));
    await _pump(tester, _page(realRequests: rows.reversed.toList()));
    expect(find.text('Expiry 4'), findsOneWidget);
    expect(find.text('Expiry 0'), findsNothing);
    expect(tester.getTopLeft(find.text('Expiry 4')).dy,
        lessThan(tester.getTopLeft(find.text('Expiry 3')).dy));
    await tester.ensureVisible(find.text('View all').first);
    await tester.tap(find.text('View all').first);
    await tester.pumpAndSettle();
    expect(find.text('Expiry 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('How rewards work'), findsOneWidget);
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
    final card = find.byKey(const ValueKey('approved-active-request-card'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(find.text('View offers  ›'), findsNothing);
    expect(find.text('PIN'), findsNothing);
    await tester.tap(card);
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
    MeetingView? pinMeeting;
    await _pump(
      tester,
      _page(
        realRequests: [BuyerRequestView.fromRequest(_request(id: meeting.requestId))],
        realMeetings: [meeting],
        onOpenMeeting: (value) => opened = value,
        onOpenPinMeeting: (value) => pinMeeting = value,
      ),
    );
    final card = find.byKey(const ValueKey('approved-active-request-card'));
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(124, 0));
    await tester.pumpAndSettle();
    expect(find.text('Purchase PIN'), findsNothing);
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(-124, 0));
    await tester.pumpAndSettle();
    expect(find.text('Choose a seller to access the purchase PIN.'), findsOneWidget);
    expect(pinMeeting, isNull);
    expect(opened, isNull);
    await tester.tap(find.byKey(const ValueKey('buyer-modal-sheet-close')));
    await tester.pumpAndSettle();
    await _pump(tester, _page(
      realRequests: [BuyerRequestView.fromRequest(
        _request(id: meeting.requestId, purchaseOfferId: meeting.offerId),
      )],
      realMeetings: [meeting],
      onOpenMeeting: (value) => opened = value,
      onOpenPinMeeting: (value) => pinMeeting = value,
    ));
    await tester.ensureVisible(card);
    await tester.drag(card, const Offset(-124, 0));
    expect(pinMeeting?.meetingId, meeting.meetingId);
    expect(opened, isNull);
    final row = find.byKey(const ValueKey('buyerMeeting-meeting-42'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(find.text('Real item'), findsOneWidget);
    await tester.tap(row);
    expect(opened?.meetingId, 'meeting-42');
  });

  testWidgets('request card opens offers and editing stays in its menu', (tester) async {
    BuyerRequestView? opened;
    BuyerRequestView? edited;
    BuyerRequestView? closeRequested;
    await _pump(
      tester,
      _page(
        realRequests: [
          BuyerRequestView.fromRequest(
            _request(id: '30000000-0000-4000-8000-000000000042'),
          ),
        ],
        onOpenOffers: (view) => opened = view,
        onOpenRequest: (view) => edited = view,
        onCloseFromHome: (view) => closeRequested = view,
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
    expect(edited, isNull);
    expect(find.byTooltip('Request options'), findsNothing);
    await tester.longPress(
      find.byKey(const ValueKey('approved-active-request-card')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit request'));
    await tester.pumpAndSettle();
    expect(edited?.requestId, opened?.requestId);
    expect(closeRequested, isNull);
    await tester.longPress(
      find.byKey(const ValueKey('approved-active-request-card')).first,
    );
    await tester.pumpAndSettle();
    expect(closeRequested, isNull);
    await tester.tap(find.text('Close request'));
    await tester.pumpAndSettle();
    expect(closeRequested?.requestId, opened?.requestId);
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
