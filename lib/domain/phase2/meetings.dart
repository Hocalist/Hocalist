/// Meeting, reschedule and PIN outcome contracts for Phase 2.
///
/// A meeting keeps the accepted schedule history linked by revision, the
/// offer revision it is based on, and a PIN *state* only. The PIN value is
/// issued, stored and validated by the server; no plaintext PIN appears in
/// any persisted model here (SEC-12).
///
/// PIN expiry is the start of the next local day after the accepted meeting
/// day, expressed as an exclusive [LocalDate]. Converting that date to a UTC
/// instant requires the agreed timezone mechanism and is backend work; this
/// file never adds a fixed 24 hours and never converts timezones.
library;

import 'common.dart';
import 'schedule.dart';

enum MeetingStatus { proposed, scheduled, completed, cancelled, expired }

enum RescheduleProposalStatus {
  proposed,
  accepted,
  declined,
  withdrawn,
  superseded,
}

/// Server-owned PIN lifecycle state for one meeting.
enum MeetingPinStatus { notIssued, active, verified, expired }

/// Server-owned PIN metadata. Deliberately contains no PIN value.
class MeetingPinState {
  MeetingPinState({
    required this.status,
    DateTime? issuedAt,
    this.expiresOnLocalDateExclusive,
    this.timezoneId,
    this.attemptCount = 0,
    DateTime? verifiedAt,
    this.verifiedByUserId,
  }) : issuedAt = issuedAt?.toUtc(),
       verifiedAt = verifiedAt?.toUtc() {
    if (attemptCount < 0) {
      throw ArgumentError.value(
        attemptCount,
        'attemptCount',
        'must not be negative',
      );
    }
    if (status == MeetingPinStatus.active) {
      if (issuedAt == null ||
          expiresOnLocalDateExclusive == null ||
          timezoneId == null) {
        throw ArgumentError(
          'an active PIN state needs issuedAt, the exclusive expiry date and '
          'the meeting timezone',
        );
      }
    }
    if (status == MeetingPinStatus.verified && verifiedAt == null) {
      throw ArgumentError('a verified PIN state needs verifiedAt');
    }
  }

  /// A meeting that does not have a usable PIN yet.
  static MeetingPinState notIssued() =>
      MeetingPinState(status: MeetingPinStatus.notIssued);

  /// The exclusive expiry date for a PIN: the start of the next local day
  /// after the accepted meeting day. Calendar arithmetic only.
  static LocalDate expiryForAcceptedDay(LocalDate acceptedLocalDate) =>
      acceptedLocalDate.nextDay();

  final MeetingPinStatus status;

  /// Server time when the PIN was issued.
  final DateTime? issuedAt;

  /// First instant the PIN is no longer usable, expressed as a local calendar
  /// date. The PIN is valid while `localToday < expiresOnLocalDateExclusive`.
  final LocalDate? expiresOnLocalDateExclusive;

  /// IANA timezone the expiry date refers to.
  final String? timezoneId;

  /// Server-owned attempt counter.
  final int attemptCount;

  final DateTime? verifiedAt;

  /// Seller identity that completed verification.
  final String? verifiedByUserId;

  bool get isActive => status == MeetingPinStatus.active;

  bool get isVerified => status == MeetingPinStatus.verified;

  /// True while the PIN may still be submitted on [localToday].
  bool isUsableOn(LocalDate localToday) {
    final expiry = expiresOnLocalDateExclusive;
    if (!isActive || expiry == null) return false;
    return localToday.isBefore(expiry);
  }

  @override
  String toString() =>
      'MeetingPinState(${status.name}, attempts: $attemptCount, '
      'expiresOn: $expiresOnLocalDateExclusive, tz: $timezoneId)';
}

/// One accepted schedule revision. History is ordered by ascending revision.
class AcceptedScheduleRevision {
  AcceptedScheduleRevision({
    required this.revision,
    required this.schedule,
    required this.place,
    required DateTime acceptedAt,
    required String acceptedByUserId,
    this.sourceProposalId,
  }) : acceptedAt = acceptedAt.toUtc(),
       acceptedByUserId = requireNonBlank(
         acceptedByUserId,
         'acceptedByUserId',
       ) {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final int revision;
  final LocalSchedule schedule;
  final MeetingPlace place;
  final DateTime acceptedAt;
  final String acceptedByUserId;

  /// Reschedule proposal that produced this revision, when applicable.
  final String? sourceProposalId;

  @override
  String toString() => 'AcceptedScheduleRevision($revision, $schedule, $place)';
}

/// A participant-proposed change to the accepted schedule.
class RescheduleProposal {
  RescheduleProposal({
    required String id,
    required String meetingId,
    required String proposedByUserId,
    required this.proposedSchedule,
    this.proposedPlace,
    this.note,
    required this.status,
    required DateTime createdAt,
    DateTime? respondedAt,
    required this.expectedMeetingRevision,
  }) : id = requireNonBlank(id, 'id'),
       meetingId = requireNonBlank(meetingId, 'meetingId'),
       proposedByUserId = requireNonBlank(proposedByUserId, 'proposedByUserId'),
       createdAt = createdAt.toUtc(),
       respondedAt = respondedAt?.toUtc() {
    if (expectedMeetingRevision < 1) {
      throw ArgumentError.value(
        expectedMeetingRevision,
        'expectedMeetingRevision',
        'must be at least 1',
      );
    }
    if (status == RescheduleProposalStatus.proposed && respondedAt != null) {
      throw ArgumentError('a proposed reschedule has not been responded to');
    }
    if ((status == RescheduleProposalStatus.accepted ||
            status == RescheduleProposalStatus.declined) &&
        respondedAt == null) {
      throw ArgumentError(
        'an accepted or declined reschedule needs respondedAt',
      );
    }
  }

  final String id;
  final String meetingId;
  final String proposedByUserId;
  final LocalSchedule proposedSchedule;
  final MeetingPlace? proposedPlace;
  final String? note;
  final RescheduleProposalStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  /// Meeting revision the proposal was made against.
  final int expectedMeetingRevision;

  @override
  String toString() =>
      'RescheduleProposal($id, meeting: $meetingId, ${status.name}, '
      '$proposedSchedule)';
}

/// A meeting linked to its request, conversation, offer and offer revision.
class Meeting {
  Meeting({
    required String id,
    required String requestId,
    required String conversationId,
    required String offerId,
    required String acceptedOfferRevisionId,
    required String buyerUserId,
    required String sellerUserId,
    required List<AcceptedScheduleRevision> acceptedScheduleHistory,
    required this.pin,
    required this.status,
    required this.stamp,
    List<RescheduleProposal> rescheduleProposals = const [],
  }) : id = requireNonBlank(id, 'id'),
       requestId = requireNonBlank(requestId, 'requestId'),
       conversationId = requireNonBlank(conversationId, 'conversationId'),
       offerId = requireNonBlank(offerId, 'offerId'),
       acceptedOfferRevisionId = requireNonBlank(
         acceptedOfferRevisionId,
         'acceptedOfferRevisionId',
       ),
       buyerUserId = requireNonBlank(buyerUserId, 'buyerUserId'),
       sellerUserId = requireNonBlank(sellerUserId, 'sellerUserId'),
       acceptedScheduleHistory = List<AcceptedScheduleRevision>.unmodifiable(
         acceptedScheduleHistory,
       ),
       rescheduleProposals = List<RescheduleProposal>.unmodifiable(
         rescheduleProposals,
       ) {
    _validateHistory();
    _validateProposals();
  }

  final String id;
  final String requestId;
  final String conversationId;
  final String offerId;

  /// Offer revision the deal terms are based on.
  final String acceptedOfferRevisionId;

  final String buyerUserId;
  final String sellerUserId;

  /// Ordered by ascending revision. The last entry is the accepted revision.
  final List<AcceptedScheduleRevision> acceptedScheduleHistory;

  final List<RescheduleProposal> rescheduleProposals;

  /// Server-owned PIN metadata, never the PIN value.
  final MeetingPinState pin;

  /// Server-owned meeting lifecycle status.
  final MeetingStatus status;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  AcceptedScheduleRevision get currentAcceptedRevision =>
      acceptedScheduleHistory.last;

  /// The open reschedule proposal, if any.
  RescheduleProposal? get pendingRescheduleProposal {
    for (final proposal in rescheduleProposals) {
      if (proposal.status == RescheduleProposalStatus.proposed) {
        return proposal;
      }
    }
    return null;
  }

  Meeting copyWith({
    List<AcceptedScheduleRevision>? acceptedScheduleHistory,
    List<RescheduleProposal>? rescheduleProposals,
    MeetingPinState? pin,
    MeetingStatus? status,
    RecordStamp? stamp,
  }) {
    return Meeting(
      id: id,
      requestId: requestId,
      conversationId: conversationId,
      offerId: offerId,
      acceptedOfferRevisionId: acceptedOfferRevisionId,
      buyerUserId: buyerUserId,
      sellerUserId: sellerUserId,
      acceptedScheduleHistory:
          acceptedScheduleHistory ?? this.acceptedScheduleHistory,
      rescheduleProposals: rescheduleProposals ?? this.rescheduleProposals,
      pin: pin ?? this.pin,
      status: status ?? this.status,
      stamp: stamp ?? this.stamp,
    );
  }

  void _validateHistory() {
    if (acceptedScheduleHistory.isEmpty) {
      throw ArgumentError.value(
        acceptedScheduleHistory,
        'acceptedScheduleHistory',
        'a meeting needs at least one accepted schedule revision',
      );
    }
    var previousRevision = 0;
    for (final entry in acceptedScheduleHistory) {
      if (entry.revision <= previousRevision) {
        throw ArgumentError.value(
          entry.revision,
          'acceptedScheduleHistory',
          'schedule revisions must ascend',
        );
      }
      previousRevision = entry.revision;
    }
  }

  void _validateProposals() {
    final ids = <String>{};
    for (final proposal in rescheduleProposals) {
      if (proposal.meetingId != id) {
        throw ArgumentError.value(
          proposal.meetingId,
          'rescheduleProposals',
          'proposal ${proposal.id} belongs to another meeting',
        );
      }
      if (!ids.add(proposal.id)) {
        throw ArgumentError.value(
          proposal.id,
          'rescheduleProposals',
          'duplicate proposal id',
        );
      }
    }
  }

  @override
  String toString() =>
      'Meeting($id, ${status.name}, revisions: '
      '${acceptedScheduleHistory.length}, pin: ${pin.status.name})';
}

/// Confirms the accepted meeting schedule for the selected offer revision.
class ConfirmMeetingCommand {
  ConfirmMeetingCommand({
    required String meetingId,
    required this.expectedRevision,
    required String acceptedOfferRevisionId,
    required this.schedule,
    required this.place,
    this.note,
    required String idempotencyKey,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       acceptedOfferRevisionId = requireNonBlank(
         acceptedOfferRevisionId,
         'acceptedOfferRevisionId',
       ),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String meetingId;
  final int expectedRevision;
  final String acceptedOfferRevisionId;
  final LocalSchedule schedule;
  final MeetingPlace place;
  final String? note;
  final String idempotencyKey;
}

/// Proposes a new date, time or place without changing the accepted revision.
class ProposeRescheduleCommand {
  ProposeRescheduleCommand({
    required String meetingId,
    required this.expectedRevision,
    required this.proposedSchedule,
    this.proposedPlace,
    this.note,
    required String idempotencyKey,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String meetingId;
  final int expectedRevision;
  final LocalSchedule proposedSchedule;
  final MeetingPlace? proposedPlace;
  final String? note;
  final String idempotencyKey;
}

/// Accepts or declines an open reschedule proposal.
///
/// Accepting creates a new accepted schedule revision server-side and
/// recomputes the PIN expiry from the new accepted day.
class RespondToRescheduleCommand {
  RespondToRescheduleCommand({
    required String meetingId,
    required String proposalId,
    required this.expectedRevision,
    required this.accept,
    required String idempotencyKey,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       proposalId = requireNonBlank(proposalId, 'proposalId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String meetingId;
  final String proposalId;
  final int expectedRevision;
  final bool accept;
  final String idempotencyKey;
}

/// Cancels the meeting. Cancellation policy for fees and reservations is
/// unresolved and is not modelled.
class CancelMeetingCommand {
  CancelMeetingCommand({
    required String meetingId,
    required this.expectedRevision,
    required String idempotencyKey,
    this.reason,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String meetingId;
  final int expectedRevision;
  final String idempotencyKey;
  final String? reason;
}

/// Shape guard shared by PIN input and display contracts.
///
/// The current app issues a five-digit PIN, and five digits must always pass.
/// Accepting 4-8 digits is only a format guard so this model does not encode an
/// unapproved length rule; the exact server policy remains open.
bool isValidPinShape(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

/// Submits the buyer-shown PIN for server verification.
///
/// The PIN travels in this transient command only. It is never stored in a
/// model, logged or echoed in [PinVerificationOutcome] or [toString].
class SubmitPinCommand {
  SubmitPinCommand({
    required String meetingId,
    required String sellerUserId,
    required this.pin,
    required String idempotencyKey,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       sellerUserId = requireNonBlank(sellerUserId, 'sellerUserId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (!isValidPinShape(pin)) {
      throw ArgumentError.value(
        '[redacted]',
        'pin',
        'must be 4 to 8 digits; the current app issues a 5-digit PIN and the '
            'exact server length is not yet decided',
      );
    }
  }

  final String meetingId;
  final String sellerUserId;
  final String pin;
  final String idempotencyKey;

  @override
  String toString() =>
      'SubmitPinCommand(meetingId: $meetingId, sellerUserId: $sellerUserId, '
      'pin: [redacted], idempotencyKey: $idempotencyKey)';
}

/// Transient buyer-only PIN display for the "After the meetup" screen.
///
/// The code is delivered only to the authenticated buyer for one specific
/// meeting and is never persisted: it is not part of [Meeting], public queries,
/// caches, logs or notification payloads. The server must re-check buyer
/// participation, accepted schedule, PIN status and expiry on every retrieval.
///
/// Delivery alternative for review: the backend may instead expose the code
/// only inside a short-lived authenticated response scoped to the meeting
/// (no push/SMS/email copy, since PINs must stay out of notification content
/// per SEC-15). This batch implements neither path.
class BuyerPinDisplay {
  BuyerPinDisplay({
    required String meetingId,
    required this.pin,
    required this.expiresOnLocalDateExclusive,
    required String timezoneId,
    DateTime? issuedAt,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       timezoneId = requireNonBlank(timezoneId, 'timezoneId'),
       issuedAt = issuedAt?.toUtc() {
    if (!isValidPinShape(pin)) {
      throw ArgumentError.value(
        '[redacted]',
        'pin',
        'must be 4 to 8 digits; the current app issues a 5-digit PIN and the '
            'exact server length is not yet decided',
      );
    }
  }

  final String meetingId;
  final String pin;
  final LocalDate expiresOnLocalDateExclusive;
  final String timezoneId;
  final DateTime? issuedAt;

  /// True while the displayed code may still be shown/submitted on
  /// [localToday]; the expiry date itself is exclusive.
  bool isUsableOn(LocalDate localToday) =>
      localToday.isBefore(expiresOnLocalDateExclusive);

  /// Redacted on purpose: the code must never reach logs.
  @override
  String toString() =>
      'BuyerPinDisplay(meetingId: $meetingId, pin: [redacted], '
      'expiresOn: $expiresOnLocalDateExclusive, tz: $timezoneId)';
}

/// Server result of one PIN submission.
enum PinVerificationOutcomeStatus {
  verified,
  wrongPin,
  expired,
  alreadyUsed,
  notEligible,
  attemptsExhausted,
}

/// Server-owned outcome of a PIN submission. Never contains the PIN value.
class PinVerificationOutcome {
  PinVerificationOutcome({
    required String meetingId,
    required this.status,
    DateTime? verifiedAt,
    this.attemptsRemaining,
  }) : meetingId = requireNonBlank(meetingId, 'meetingId'),
       verifiedAt = verifiedAt?.toUtc() {
    if (attemptsRemaining != null && attemptsRemaining! < 0) {
      throw ArgumentError.value(
        attemptsRemaining,
        'attemptsRemaining',
        'must not be negative',
      );
    }
  }

  final String meetingId;
  final PinVerificationOutcomeStatus status;

  /// Server verification time when [status] is
  /// [PinVerificationOutcomeStatus.verified].
  final DateTime? verifiedAt;

  /// Remaining attempts when the server reports a limit.
  final int? attemptsRemaining;

  bool get isVerified => status == PinVerificationOutcomeStatus.verified;

  @override
  String toString() =>
      'PinVerificationOutcome($meetingId, ${status.name}, '
      'verifiedAt: $verifiedAt)';
}
