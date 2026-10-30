import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/meetings/meeting_codecs.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/chat/conversation_meeting_actions.dart';

MeetingView meeting({
  bool accepted = false,
  String? proposer = 'seller',
  bool chosen = true,
  String id = 'meeting',
}) {
  MeetingScheduleView schedule(String status) => MeetingScheduleView(
    sequence: 1,
    date: LocalDate(year: 2026, month: 10, day: 18),
    startTime: LocalTime(hour: 14, minute: 30),
    timezoneId: 'America/Chicago',
    offsetMinutes: -300,
    instant: DateTime.utc(2026, 10, 18, 19, 30),
    placeChoice: 'specific_place',
    placeLabel: 'Test library',
    proposedByUserId: proposer ?? 'seller',
    status: status,
    createdAt: DateTime.utc(2026, 10, 17),
  );
  return MeetingView(
    meetingId: id,
    conversationId: 'chat',
    requestId: 'request-$id',
    offerId: 'offer-$id',
    buyerUserId: 'buyer',
    sellerUserId: 'seller',
    status: accepted ? 'accepted' : 'proposed',
    revision: 1,
    acceptedSchedule: accepted ? schedule('accepted') : null,
    pendingSchedule: proposer == null ? null : schedule('proposed'),
    purchaseSelected: chosen,
    revisions: [],
  );
}

Future<void> pump(
  WidgetTester tester, {
  required MeetingView deal,
  String user = 'buyer',
  bool completed = false,
  Future<void> Function(MeetingView)? accept,
  double width = 390,
  double scale = 1,
  List<MeetingView>? deals,
  String? selectedDealId,
  bool compact = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConversationMeetingActions(
            compact: compact,
            meetings: deals ?? [deal],
            selectedDealId: selectedDealId,
            viewerUserId: user,
            completedIds: completed ? {deal.meetingId} : {},
            onAccept: accept ?? (_) async {},
            onDecline: (_) async {},
            onReschedule: (_) async {},
            onDirections: (_) async {},
            onChoosePurchase: (_) async {},
            onReview: (_) async {},
            confirmationBuilder: (_) => Text(
              user == 'buyer' ? 'Buyer PIN controls' : 'Seller PIN entry',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'compact meeting controls stay usable across phone widths and text scales',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.15, 1.3, 1.6]) {
          var accepted = false;
          await pump(
            tester,
            deal: meeting(),
            compact: true,
            width: width,
            scale: scale,
            accept: (_) async {
              accepted = true;
            },
          );
          await tester.tap(find.text('Accept meeting'));
          await tester.pumpAndSettle();
          expect(accepted, isTrue);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'compact accepted purchase controls expand explicitly and completion removes them',
    (tester) async {
      final deal = meeting(accepted: true, proposer: null);
      await pump(tester, deal: deal, compact: true);
      expect(find.text('Your purchase PIN'), findsOneWidget);
      await tester.tap(find.text('Your purchase PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Buyer PIN controls'), findsOneWidget);
      await pump(tester, deal: deal, compact: true, completed: true);
      expect(find.text('Your purchase PIN'), findsNothing);
      expect(find.text('Review your purchase'), findsOneWidget);
      expect(find.text('Directions'), findsNothing);
    },
  );
  testWidgets(
    'pending change blocks PIN and overlapping changes for both roles',
    (tester) async {
      for (final user in ['buyer', 'seller']) {
        await pump(tester, deal: meeting(accepted: true), user: user);
        expect(find.text('Buyer PIN controls'), findsNothing);
        expect(find.text('Seller PIN entry'), findsNothing);
        expect(find.text('Propose a new date or time'), findsNothing);
        expect(
          find.text('Accept meeting'),
          user == 'buyer' ? findsOneWidget : findsNothing,
        );
      }
    },
  );

  testWidgets(
    'a selected deal without a meeting never inherits another deal actions',
    (tester) async {
      await pump(
        tester,
        deal: meeting(),
        selectedDealId: 'offer-without-meeting',
      );
      expect(find.text('Accept meeting'), findsNothing);
      expect(find.text('Your meeting is set'), findsNothing);
    },
  );
  testWidgets('card-selected deal controls acceptance without a dropdown', (
    tester,
  ) async {
    final first = meeting(id: 'first', proposer: 'seller');
    final second = meeting(id: 'second', proposer: 'buyer');
    await pump(
      tester,
      deal: second,
      deals: [first, second],
      selectedDealId: 'offer-second',
    );
    expect(find.text('Waiting for acceptance'), findsOneWidget);
    expect(find.text('Accept meeting'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
  testWidgets('confirmed seller: recipient accepts and proposer waits', (
    tester,
  ) async {
    await pump(tester, deal: meeting());
    expect(find.text('Accept meeting'), findsOneWidget);
    expect(find.text('Decline proposed time'), findsOneWidget);
    expect(find.text('Confirm this seller'), findsNothing);
    expect(find.text('Buyer PIN controls'), findsNothing);
    await pump(tester, deal: meeting(), user: 'seller');
    expect(find.text('Waiting for acceptance'), findsOneWidget);
    expect(find.text('Accept meeting'), findsNothing);
    expect(find.text('Decline proposed time'), findsNothing);
    expect(find.text('Confirm this seller'), findsNothing);
  });
  testWidgets('seller confirmation precedes all meeting controls', (
    tester,
  ) async {
    await pump(tester, deal: meeting(chosen: false));
    expect(find.text('Confirm this seller'), findsOneWidget);
    expect(find.text('Accept meeting'), findsNothing);
    expect(find.text('Decline proposed time'), findsNothing);
    expect(find.text('Buyer PIN controls'), findsNothing);
    await pump(tester, deal: meeting(chosen: false), user: 'seller');
    expect(find.text('Waiting for buyer confirmation'), findsOneWidget);
    expect(find.text('Confirm this seller'), findsNothing);
    expect(find.text('Accept meeting'), findsNothing);
  });
  testWidgets(
    'accepted meeting exposes role-specific PIN and reschedule in chat',
    (tester) async {
      for (final user in ['buyer', 'seller']) {
        await pump(
          tester,
          deal: meeting(accepted: true, proposer: null, chosen: true),
          user: user,
        );
        expect(find.text('Your meeting is set'), findsOneWidget);
        expect(find.text('Propose a new date or time'), findsOneWidget);
        expect(
          find.text(
            user == 'buyer' ? 'Buyer PIN controls' : 'Seller PIN entry',
          ),
          findsOneWidget,
        );
        expect(find.text('Accept meeting'), findsNothing);
      }
    },
  );
  testWidgets(
    'completion removes directions and PIN; review belongs to buyer',
    (tester) async {
      for (final user in ['buyer', 'seller']) {
        await pump(
          tester,
          deal: meeting(accepted: true, proposer: null),
          user: user,
          completed: true,
        );
        expect(find.text('Purchase completed'), findsOneWidget);
        expect(find.text('View directions'), findsNothing);
        expect(find.text('Propose a new date or time'), findsNothing);
        expect(find.text('Buyer PIN controls'), findsNothing);
        expect(find.text('Seller PIN entry'), findsNothing);
        expect(
          find.text('Review your purchase'),
          user == 'buyer' ? findsOneWidget : findsNothing,
        );
      }
    },
  );
  testWidgets(
    'double tap cannot send two decisions and the exact meeting is passed',
    (tester) async {
      final gate = Completer<void>();
      final ids = <String>[];
      await pump(
        tester,
        deal: meeting(id: 'specific'),
        accept: (m) async {
          ids.add(m.meetingId);
          await gate.future;
        },
      );
      await tester.tap(find.text('Accept meeting'));
      await tester.pump();
      await tester.tap(find.text('Accept meeting'));
      await tester.pump();
      expect(ids, ['specific']);
      gate.complete();
      await tester.pumpAndSettle();
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('meeting actions fit $width at $scale', (tester) async {
        await pump(
          tester,
          deal: meeting(accepted: true),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
