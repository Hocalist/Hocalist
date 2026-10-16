import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final place = MeetingPlace(
    choice: MeetupPlaceChoice.specificPlace,
    label: 'Cross County Mall',
    placeId: 'place-1',
  );

  LocalSchedule scheduleOn(LocalDate date) => LocalSchedule(
    date: date,
    startTime: LocalTime(hour: 15, minute: 0),
    timezoneId: 'America/New_York',
  );

  AcceptedScheduleRevision acceptedRevision(
    int revision,
    LocalDate date, {
    String? sourceProposalId,
  }) => AcceptedScheduleRevision(
    revision: revision,
    schedule: scheduleOn(date),
    place: place,
    acceptedAt: DateTime.utc(2026, 5, 1),
    acceptedByUserId: 'auth-buyer',
    sourceProposalId: sourceProposalId,
  );

  MeetingPinState activePinFor(LocalDate acceptedDay) => MeetingPinState(
    status: MeetingPinStatus.active,
    issuedAt: DateTime.utc(2026, 5, 1),
    expiresOnLocalDateExclusive: MeetingPinState.expiryForAcceptedDay(
      acceptedDay,
    ),
    timezoneId: 'America/New_York',
  );

  Meeting meetingWith({
    List<AcceptedScheduleRevision>? history,
    List<RescheduleProposal> proposals = const [],
    MeetingPinState? pin,
    MeetingStatus status = MeetingStatus.scheduled,
  }) {
    final acceptedDay = LocalDate(year: 2026, month: 5, day: 20);
    return Meeting(
      id: 'meeting-1',
      requestId: 'request-1',
      conversationId: 'conversation-1',
      offerId: 'offer-1',
      acceptedOfferRevisionId: 'rev-2',
      buyerUserId: 'auth-buyer',
      sellerUserId: 'auth-seller',
      acceptedScheduleHistory: history ?? [acceptedRevision(1, acceptedDay)],
      pin: pin ?? activePinFor(acceptedDay),
      status: status,
      stamp: RecordStamp(
        revision: 1,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
      rescheduleProposals: proposals,
    );
  }

  group('PIN expiry', () {
    test('is the start of the next local day, not a 24-hour offset', () {
      expect(
        MeetingPinState.expiryForAcceptedDay(
          LocalDate(year: 2026, month: 5, day: 31),
        ),
        LocalDate(year: 2026, month: 6, day: 1),
      );
      expect(
        MeetingPinState.expiryForAcceptedDay(
          LocalDate(year: 2024, month: 2, day: 28),
        ),
        LocalDate(year: 2024, month: 2, day: 29),
      );
      expect(
        MeetingPinState.expiryForAcceptedDay(
          LocalDate(year: 2025, month: 12, day: 31),
        ),
        LocalDate(year: 2026, month: 1, day: 1),
      );
    });

    test('is exclusive: usable on the meeting day, not on the next day', () {
      final pin = activePinFor(LocalDate(year: 2026, month: 5, day: 20));

      expect(
        pin.expiresOnLocalDateExclusive,
        LocalDate(year: 2026, month: 5, day: 21),
      );
      expect(pin.isUsableOn(LocalDate(year: 2026, month: 5, day: 20)), isTrue);
      expect(pin.isUsableOn(LocalDate(year: 2026, month: 5, day: 21)), isFalse);
    });

    test(
      'expiry carries the accepted meeting timezone, never a fixed offset',
      () {
        final pin = activePinFor(LocalDate(year: 2026, month: 5, day: 20));

        expect(pin.timezoneId, 'America/New_York');
      },
    );

    test('an active state needs issue time, expiry and timezone', () {
      expect(
        () => MeetingPinState(status: MeetingPinStatus.active),
        throwsArgumentError,
      );
      expect(
        () => MeetingPinState(status: MeetingPinStatus.verified),
        throwsArgumentError,
      );
      expect(
        MeetingPinState(
          status: MeetingPinStatus.verified,
          verifiedAt: DateTime.utc(2026, 5, 20),
        ).isVerified,
        isTrue,
      );
      expect(MeetingPinState.notIssued().isActive, isFalse);
      expect(
        () => MeetingPinState(
          status: MeetingPinStatus.notIssued,
          attemptCount: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Meeting accepted revision', () {
    test('exposes the last accepted schedule revision', () {
      final meeting = meetingWith();

      expect(meeting.currentAcceptedRevision.revision, 1);
      expect(meeting.currentAcceptedRevision.schedule.date.day, 20);
      expect(meeting.acceptedOfferRevisionId, 'rev-2');
      expect(meeting.pendingRescheduleProposal, isNull);
    });

    test('accepting a reschedule adds a revision and moves the PIN expiry', () {
      final rescheduledDay = LocalDate(year: 2026, month: 5, day: 25);
      final proposal = RescheduleProposal(
        id: 'proposal-1',
        meetingId: 'meeting-1',
        proposedByUserId: 'auth-seller',
        proposedSchedule: scheduleOn(rescheduledDay),
        note: 'Running late that week.',
        status: RescheduleProposalStatus.accepted,
        createdAt: DateTime.utc(2026, 5, 2),
        respondedAt: DateTime.utc(2026, 5, 3),
        expectedMeetingRevision: 1,
      );

      final updated = meetingWith(proposals: [proposal]).copyWith(
        acceptedScheduleHistory: [
          acceptedRevision(1, LocalDate(year: 2026, month: 5, day: 20)),
          acceptedRevision(2, rescheduledDay, sourceProposalId: 'proposal-1'),
        ],
        pin: activePinFor(rescheduledDay),
        stamp: RecordStamp(
          revision: 2,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 3),
        ),
      );

      expect(updated.currentAcceptedRevision.revision, 2);
      expect(updated.currentAcceptedRevision.sourceProposalId, 'proposal-1');
      expect(
        updated.pin.expiresOnLocalDateExclusive,
        LocalDate(year: 2026, month: 5, day: 26),
      );
      expect(updated.stamp.revision, 2);
      expect(updated.rescheduleProposals.single.id, 'proposal-1');
    });

    test('history must be non-empty and ascend by revision', () {
      expect(() => meetingWith(history: const []), throwsArgumentError);
      expect(
        () => meetingWith(
          history: [
            acceptedRevision(2, LocalDate(year: 2026, month: 5, day: 20)),
            acceptedRevision(1, LocalDate(year: 2026, month: 5, day: 21)),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('RescheduleProposal', () {
    test('open proposals cannot already have a response', () {
      expect(
        () => RescheduleProposal(
          id: 'proposal-1',
          meetingId: 'meeting-1',
          proposedByUserId: 'auth-seller',
          proposedSchedule: scheduleOn(
            LocalDate(year: 2026, month: 5, day: 25),
          ),
          status: RescheduleProposalStatus.proposed,
          createdAt: DateTime.utc(2026, 5, 2),
          respondedAt: DateTime.utc(2026, 5, 3),
          expectedMeetingRevision: 1,
        ),
        throwsArgumentError,
      );
    });

    test('accepted proposals need a response time', () {
      expect(
        () => RescheduleProposal(
          id: 'proposal-1',
          meetingId: 'meeting-1',
          proposedByUserId: 'auth-seller',
          proposedSchedule: scheduleOn(
            LocalDate(year: 2026, month: 5, day: 25),
          ),
          status: RescheduleProposalStatus.accepted,
          createdAt: DateTime.utc(2026, 5, 2),
          expectedMeetingRevision: 1,
        ),
        throwsArgumentError,
      );
    });

    test('a meeting rejects a proposal that belongs to another meeting', () {
      final foreignProposal = RescheduleProposal(
        id: 'proposal-9',
        meetingId: 'meeting-9',
        proposedByUserId: 'auth-seller',
        proposedSchedule: scheduleOn(LocalDate(year: 2026, month: 5, day: 25)),
        status: RescheduleProposalStatus.proposed,
        createdAt: DateTime.utc(2026, 5, 2),
        expectedMeetingRevision: 1,
      );

      expect(
        () => meetingWith(proposals: [foreignProposal]),
        throwsArgumentError,
      );
    });

    test('an open proposal is reported as pending', () {
      final proposal = RescheduleProposal(
        id: 'proposal-1',
        meetingId: 'meeting-1',
        proposedByUserId: 'auth-seller',
        proposedSchedule: scheduleOn(LocalDate(year: 2026, month: 5, day: 25)),
        status: RescheduleProposalStatus.proposed,
        createdAt: DateTime.utc(2026, 5, 2),
        expectedMeetingRevision: 1,
      );

      expect(
        meetingWith(proposals: [proposal]).pendingRescheduleProposal?.id,
        'proposal-1',
      );
    });
  });

  group('PIN submission', () {
    test('accepts the current five-digit app PIN', () {
      expect(isValidPinShape('15230'), isTrue);

      final command = SubmitPinCommand(
        meetingId: 'meeting-1',
        sellerUserId: 'auth-seller',
        pin: '15230',
        idempotencyKey: 'pin-1',
      );
      expect(command.pin, '15230');
    });

    test('never renders the PIN value in toString', () {
      final command = SubmitPinCommand(
        meetingId: 'meeting-1',
        sellerUserId: 'auth-seller',
        pin: '15230',
        idempotencyKey: 'pin-1',
      );

      expect(command.toString().contains('15230'), isFalse);
      expect(command.toString(), contains('[redacted]'));
    });

    test('rejected PIN input is not echoed in the error text', () {
      try {
        SubmitPinCommand(
          meetingId: 'meeting-1',
          sellerUserId: 'auth-seller',
          pin: 'SENTINEL-PIN',
          idempotencyKey: 'pin-1',
        );
        fail('expected an ArgumentError');
      } on ArgumentError catch (error) {
        final rendered = error.toString();
        expect(rendered.contains('SENTINEL-PIN'), isFalse);
        expect(rendered, contains('5-digit'));
      }
    });

    test('rejects non-numeric or out-of-range PIN input', () {
      expect(isValidPinShape('12ab0'), isFalse);
      expect(isValidPinShape('123'), isFalse);
      expect(isValidPinShape('123456789'), isFalse);
      expect(
        () => SubmitPinCommand(
          meetingId: 'meeting-1',
          sellerUserId: 'auth-seller',
          pin: '12ab0',
          idempotencyKey: 'pin-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmitPinCommand(
          meetingId: 'meeting-1',
          sellerUserId: 'auth-seller',
          pin: '123',
          idempotencyKey: 'pin-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmitPinCommand(
          meetingId: 'meeting-1',
          sellerUserId: 'auth-seller',
          pin: '15230',
          idempotencyKey: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('outcomes are server-owned and never echo the PIN', () {
      final outcome = PinVerificationOutcome(
        meetingId: 'meeting-1',
        status: PinVerificationOutcomeStatus.verified,
        verifiedAt: DateTime.utc(2026, 5, 20, 19, 5),
        attemptsRemaining: 4,
      );

      expect(outcome.isVerified, isTrue);
      expect(outcome.attemptsRemaining, 4);
      expect(outcome.toString().contains('15230'), isFalse);
      expect(
        () => PinVerificationOutcome(
          meetingId: 'meeting-1',
          status: PinVerificationOutcomeStatus.wrongPin,
          attemptsRemaining: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('BuyerPinDisplay', () {
    BuyerPinDisplay display() {
      return BuyerPinDisplay(
        meetingId: 'meeting-1',
        pin: '15230',
        expiresOnLocalDateExclusive: LocalDate(year: 2026, month: 5, day: 21),
        timezoneId: 'America/New_York',
        issuedAt: DateTime.utc(2026, 5, 20, 15, 0),
      );
    }

    test('carries the code and the exclusive local expiry only', () {
      final pinDisplay = display();

      expect(pinDisplay.meetingId, 'meeting-1');
      expect(pinDisplay.pin, '15230');
      expect(pinDisplay.timezoneId, 'America/New_York');
      expect(pinDisplay.issuedAt?.isUtc, isTrue);
      expect(
        pinDisplay.expiresOnLocalDateExclusive,
        LocalDate(year: 2026, month: 5, day: 21),
      );
    });

    test('is usable on the meeting day and not on the expiry day', () {
      final pinDisplay = display();

      expect(
        pinDisplay.isUsableOn(LocalDate(year: 2026, month: 5, day: 20)),
        isTrue,
      );
      expect(
        pinDisplay.isUsableOn(LocalDate(year: 2026, month: 5, day: 21)),
        isFalse,
      );
    });

    test('never renders the code in debug output', () {
      final rendered = display().toString();

      expect(rendered.contains('15230'), isFalse);
      expect(rendered, contains('[redacted]'));
    });

    test('rejects blank ids, blank timezones and invalid codes', () {
      expect(
        () => BuyerPinDisplay(
          meetingId: ' ',
          pin: '15230',
          expiresOnLocalDateExclusive: LocalDate(year: 2026, month: 5, day: 21),
          timezoneId: 'America/New_York',
        ),
        throwsArgumentError,
      );
      expect(
        () => BuyerPinDisplay(
          meetingId: 'meeting-1',
          pin: '15230',
          expiresOnLocalDateExclusive: LocalDate(year: 2026, month: 5, day: 21),
          timezoneId: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => BuyerPinDisplay(
          meetingId: 'meeting-1',
          pin: '12ab0',
          expiresOnLocalDateExclusive: LocalDate(year: 2026, month: 5, day: 21),
          timezoneId: 'America/New_York',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Meeting commands', () {
    test('carry expected revisions and idempotency keys', () {
      final confirm = ConfirmMeetingCommand(
        meetingId: 'meeting-1',
        expectedRevision: 1,
        acceptedOfferRevisionId: 'rev-2',
        schedule: scheduleOn(LocalDate(year: 2026, month: 5, day: 20)),
        place: place,
        idempotencyKey: 'confirm-1',
      );
      expect(confirm.acceptedOfferRevisionId, 'rev-2');

      final propose = ProposeRescheduleCommand(
        meetingId: 'meeting-1',
        expectedRevision: 1,
        proposedSchedule: scheduleOn(LocalDate(year: 2026, month: 5, day: 25)),
        note: 'Traffic.',
        idempotencyKey: 'propose-1',
      );
      expect(propose.note, 'Traffic.');

      final respond = RespondToRescheduleCommand(
        meetingId: 'meeting-1',
        proposalId: 'proposal-1',
        expectedRevision: 1,
        accept: true,
        idempotencyKey: 'respond-1',
      );
      expect(respond.accept, isTrue);

      final cancel = CancelMeetingCommand(
        meetingId: 'meeting-1',
        expectedRevision: 2,
        reason: 'Seller unavailable',
        idempotencyKey: 'cancel-1',
      );
      expect(cancel.expectedRevision, 2);
    });

    test('reject revisions below one and blank keys', () {
      expect(
        () => ProposeRescheduleCommand(
          meetingId: 'meeting-1',
          expectedRevision: 0,
          proposedSchedule: scheduleOn(
            LocalDate(year: 2026, month: 5, day: 25),
          ),
          idempotencyKey: 'propose-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => CancelMeetingCommand(
          meetingId: 'meeting-1',
          expectedRevision: 1,
          idempotencyKey: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
