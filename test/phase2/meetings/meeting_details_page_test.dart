// Buyer meeting details wiring: authoritative offer summary rendering, gated
// actions and prototype fallback.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/seller/approved_seller_meets_page.dart';
import 'package:hocalist/features/seller/approved_seller_reschedule_dialog.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';

import '../../test_fonts.dart';

MeetingScheduleView _schedule({
  String? placeLabel = 'Cross County Mall',
  String? placeAddress = '123 Synthetic Ave',
  String placeChoice = 'specific_place',
  String status = 'proposed',
}) => MeetingScheduleView(
  sequence: 1,
  date: LocalDate(year: 2026, month: 10, day: 1),
  startTime: LocalTime(hour: 18, minute: 30),
  timezoneId: 'America/New_York',
  offsetMinutes: -240,
  instant: DateTime.utc(2026, 10, 1, 22, 30),
  placeChoice: placeChoice,
  placeLabel: placeLabel,
  placeAddress: placeAddress,
  proposedByUserId: 'user-a',
  status: status,
  createdAt: DateTime.utc(2026, 9, 20),
);

MeetingView _meeting({
  String meetingId = '80000000-0000-4000-8000-000000000001',
  String conversationId = '60000000-0000-4000-8000-000000000001',
  String status = 'proposed',
  bool withSummary = true,
  bool withPending = true,
  MeetingScheduleView? acceptedSchedule,
  DateTime? meetingExpiresAt,
}) => MeetingView(
  meetingId: meetingId,
  conversationId: conversationId,
  requestId: '30000000-0000-4000-8000-000000000001',
  offerId: '40000000-0000-4000-8000-000000000001',
  buyerUserId: 'user-a',
  sellerUserId: 'user-b',
  status: status,
  revision: 1,
  meetingExpiresAt: meetingExpiresAt,
  offerSummary: withSummary
      ? const MeetingOfferSummary(
          title: 'Loop Resale iPad Air',
          priceMinor: 39000,
          currencyCode: 'USD',
          revisionId: '41000000-0000-4000-8000-000000000001',
        )
      : null,
  acceptedSchedule: status == 'accepted'
      ? acceptedSchedule ?? _schedule(status: 'accepted')
      : null,
  pendingSchedule: withPending ? _schedule() : null,
  revisions: [_schedule()],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool settle = true,
  bool scroll = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: Scaffold(
        body: scroll ? SingleChildScrollView(child: child) : child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets(
    'confirmed purchase keeps meeting facts without cancel or reschedule',
    (tester) async {
      await _pump(
        tester,
        ApprovedMeetingDetailsPage(
          onBack: () {},
          onConfirm: () {},
          onCancel: () {},
          onReschedule: () {},
          meeting: _meeting(status: 'accepted', withPending: false),
          purchaseConfirmed: true,
        ),
      );
      expect(find.text('Loop Resale iPad Air'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approved-cancel-meeting-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('approved-reschedule-meeting-button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'buyer location without address keeps its choice and disables maps',
    (tester) async {
      var opened = false;
      await _pump(
        tester,
        ApprovedMeetingDetailsPage(
          onBack: () {},
          onConfirm: () {},
          onDirections: () => opened = true,
          meeting: _meeting(
            status: 'accepted',
            withPending: false,
            acceptedSchedule: _schedule(
              status: 'accepted',
              placeLabel: null,
              placeAddress: null,
              placeChoice: 'buyer_location',
            ),
          ),
        ),
      );
      final field = tester.widget<TextFormField>(
        find.descendant(
          of: find.byKey(const ValueKey('approved-meeting-location-field')),
          matching: find.byType(TextFormField),
        ),
      );
      expect(
        field.initialValue,
        'Buyer location — confirm the address in chat',
      );
      final directions = tester.widget<TextButton>(
        find.byKey(const ValueKey('approved-meeting-directions')),
      );
      expect(directions.onPressed, isNull);
      expect(opened, false);
    },
  );

  testWidgets('proposer cannot confirm their own schedule', (tester) async {
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(
        onBack: () {},
        onConfirm: () {},
        meeting: _meeting(),
        viewerUserId: 'user-a',
      ),
    );
    expect(
      find.byKey(const ValueKey('approved-confirm-meeting-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('approved-decline-meeting-button')),
      findsNothing,
    );
  });

  testWidgets('real seller list uses server rows and never exposes demo PIN', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerMeetsPage(
            onOpenChat: () {},
            meetings: [_meeting()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loop Resale iPad Air'), findsOneWidget);
    expect(find.text('America/New_York'), findsOneWidget);
    expect(find.text('Enter PIN'), findsNothing);
    expect(find.text('View meeting'), findsOneWidget);
  });

  testWidgets(
    'expired unresolved meetings remain actionable without becoming completed',
    (tester) async {
      final meeting = _meeting(
        status: 'accepted',
        meetingExpiresAt: DateTime.utc(2000),
      );
      MeetingView? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovedSellerMeetsPage(
              onOpenChat: () {},
              meetings: [meeting],
              onOpenMeeting: (value) => opened = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Past meetings · needs attention'), findsOneWidget);
      expect(find.text('Loop Resale iPad Air'), findsOneWidget);
      await tester.ensureVisible(find.text('View meeting'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View meeting'));
      expect(opened, same(meeting));
      await tester.drag(
        find.byKey(const Key('sellerRealMeets')),
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sellerMeetFilterCompleted')));
      await tester.pumpAndSettle();
      expect(find.text('Loop Resale iPad Air'), findsNothing);
    },
  );

  testWidgets('confirmed purchases are not repeated as unresolved meetings', (
    tester,
  ) async {
    final meeting = _meeting(
      status: 'accepted',
      meetingExpiresAt: DateTime.utc(2000),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerMeetsPage(
            onOpenChat: () {},
            meetings: [meeting],
            completedMeetingIds: {meeting.meetingId},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Past meetings · needs attention'), findsNothing);
    expect(find.text('Loop Resale iPad Air'), findsNothing);
    await tester.tap(find.byKey(const Key('sellerMeetFilterCompleted')));
    await tester.pumpAndSettle();
    expect(find.text('Loop Resale iPad Air'), findsOneWidget);
  });

  testWidgets('real empty seller list keeps the approved tabs and empty card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovedSellerMeetsPage(onOpenChat: () {}, meetings: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No upcoming appointments'), findsOneWidget);
    expect(
      find.text('Appointments you agree to will appear here.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sellerMeetFilterUpcoming')), findsOneWidget);
    expect(find.byKey(const Key('sellerMeetFilterToday')), findsOneWidget);
    expect(find.byKey(const Key('sellerMeetFilterCompleted')), findsOneWidget);
    expect(find.byKey(const Key('sellerMeetFilterCanceled')), findsOneWidget);
    expect(find.text('View meeting'), findsNothing);

    await tester.tap(find.byKey(const Key('sellerMeetFilterCompleted')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A meeting is completed after a verified purchase PIN outcome.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('seller card actions use their own meeting and conversation', (
    tester,
  ) async {
    final first = _meeting(status: 'accepted', withPending: false);
    final second = _meeting(
      status: 'accepted',
      withPending: false,
      meetingId: '80000000-0000-4000-8000-000000000002',
      conversationId: '60000000-0000-4000-8000-000000000002',
    );
    String? messaged, directed;
    var genericMessages = 0;
    await _pump(
      tester,
      ApprovedSellerMeetsPage(
        onOpenChat: () => genericMessages++,
        meetings: [first, second],
        onMessageMeeting: (meeting) => messaged = meeting.conversationId,
        onDirectionsMeeting: (meeting) => directed = meeting.meetingId,
      ),
      scroll: false,
    );
    final message = find.byKey(
      ValueKey('sellerRealMeetMessage-${second.meetingId}'),
    );
    await tester.ensureVisible(message);
    await tester.tap(message);
    expect(messaged, second.conversationId);
    expect(genericMessages, 0);
    final directions = find.byKey(
      ValueKey('sellerRealMeetDirections-${second.meetingId}'),
    );
    await tester.tap(directions);
    expect(directed, second.meetingId);
  });

  testWidgets(
    'generic destination keeps directions disabled and never uses another meeting',
    (tester) async {
      final meeting = _meeting(
        status: 'accepted',
        withPending: false,
        acceptedSchedule: _schedule(
          placeAddress: null,
          placeLabel: 'Seller business',
          placeChoice: 'seller_business',
          status: 'accepted',
        ),
      );
      await _pump(
        tester,
        ApprovedSellerMeetsPage(
          onOpenChat: () {},
          meetings: [meeting],
          onDirectionsMeeting: (_) =>
              fail('Generic location cannot launch directions'),
        ),
        scroll: false,
      );
      final action = find.descendant(
        of: find.byKey(
          ValueKey('sellerRealMeetDirections-${meeting.meetingId}'),
        ),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
      expect(
        find.textContaining('confirmed meeting destination'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reschedule waits for acknowledgement and reuses uncertain intent',
    (tester) async {
      final keys = <String>[];
      final futureDate = DateUtils.dateOnly(
        DateTime.now(),
      ).add(const Duration(days: 2));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovedSellerRescheduleDialog(
              customerName: 'buyer',
              currentDate: '2026-10-01',
              currentTime: '18:30',
              initialDate: futureDate,
              initialTime: const TimeOfDay(hour: 18, minute: 30),
              timezoneId: 'America/New_York',
              onSubmit: (date, time, occurrence, key) async {
                keys.add(key);
                expect(date, futureDate);
                expect(time.hour, 18);
                return const MeetingActionResult.failure(
                  'Unconfirmed',
                  outcomeUncertain: true,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('sellerSendReschedule')));
      await tester.tap(find.byKey(const Key('sellerSendReschedule')));
      await tester.pumpAndSettle();
      expect(find.text('Unconfirmed'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('sellerSendReschedule')));
      await tester.tap(find.byKey(const Key('sellerSendReschedule')));
      await tester.pumpAndSettle();
      expect(keys.length, 2);
      expect(keys.first, keys.last);
    },
  );

  testWidgets('real meeting renders the authoritative offer summary', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(
        onBack: () {},
        onConfirm: () {},
        meeting: _meeting(),
        onDecline: () {},
      ),
    );
    expect(find.text('Loop Resale iPad Air'), findsOneWidget);
    expect(find.text(r'$390'), findsOneWidget);
    expect(find.text('Meeting proposed'), findsOneWidget);
    expect(find.text('Cross County Mall'), findsOneWidget);
    expect(find.text('Oct 1 • 6:30 PM · America/New_York'), findsOneWidget);
    expect(find.text('iPad Air 5th Gen 64GB'), findsNothing);
    expect(find.text(r'$650'), findsNothing);
    expect(find.text('Yonkers, NY'), findsNothing);
  });

  testWidgets(
    'a missing summary states unavailability without inventing data',
    (tester) async {
      await _pump(
        tester,
        ApprovedMeetingDetailsPage(
          onBack: () {},
          onConfirm: () {},
          meeting: _meeting(withSummary: false),
        ),
      );
      expect(find.text('Offer details unavailable'), findsOneWidget);
      expect(find.text('iPad Air 5th Gen 64GB'), findsNothing);
      expect(find.text(r'$650'), findsNothing);
    },
  );

  testWidgets('pending meetings can be declined and accepted', (tester) async {
    var declined = 0;
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(
        onBack: () {},
        onConfirm: () {},
        meeting: _meeting(),
        onDecline: () => declined++,
      ),
    );
    expect(
      find.byKey(const ValueKey('approved-decline-meeting-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-cancel-meeting-button')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('approved-decline-meeting-button')),
    );
    await tester.pumpAndSettle();
    expect(declined, 1);
  });

  testWidgets('accepted meetings can be cancelled', (tester) async {
    var cancelled = 0;
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(
        onBack: () {},
        onConfirm: () {},
        meeting: _meeting(status: 'accepted', withPending: false),
        onCancel: () => cancelled++,
      ),
    );
    expect(
      find.byKey(const ValueKey('approved-cancel-meeting-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('approved-decline-meeting-button')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('approved-cancel-meeting-button')),
    );
    await tester.pumpAndSettle();
    expect(cancelled, 1);
  });

  testWidgets('busy and error states replace the confirm action', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(
        onBack: () {},
        onConfirm: () {},
        meeting: _meeting(),
        busy: true,
        error: 'This meeting changed. Refresh and try again.',
      ),
      settle: false,
    );
    expect(find.byKey(const ValueKey('approved-meeting-busy')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-confirm-meeting-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('approved-meeting-error')),
      findsOneWidget,
    );
  });

  testWidgets('prototype mode keeps the approved fixture rows', (tester) async {
    await _pump(
      tester,
      ApprovedMeetingDetailsPage(onBack: () {}, onConfirm: () {}),
    );
    expect(find.text('iPad Air 5th Gen 64GB'), findsOneWidget);
    expect(find.text(r'$650'), findsOneWidget);
    expect(find.text('Offer accepted'), findsOneWidget);
    expect(find.text('Yonkers, NY'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approved-decline-meeting-button')),
      findsNothing,
    );
  });
}
