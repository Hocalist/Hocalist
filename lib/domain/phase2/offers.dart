/// Seller offer contracts for Phase 2.
///
/// An offer keeps every proposed revision as a separate record linked by IDs,
/// so a request can carry multiple seller offers and each offer can carry
/// proposed, accepted and superseded terms without a single latest-offer slot.
///
/// A buyer may accept several sellers for one request (each with its own
/// conversation and meeting) and then designate one of them as the final
/// purchase seller. A confirmed purchase is owned by the server and closes
/// every other negotiation for the request.
library;

import 'common.dart';
import 'failures.dart';
import 'money.dart';
import 'schedule.dart';

/// Server-owned offer lifecycle.
///
/// `completed` is only produced by a server-verified PIN outcome; opening a
/// review or success screen never sets it (SEC-13).
enum OfferStatus {
  submitted,
  selected,
  withdrawn,
  declined,
  completed,
  cancelled,
  expired,
}

/// Server-owned status of one offer revision.
enum OfferRevisionStatus { proposed, accepted, superseded, rejected, withdrawn }

/// Complete editable offer terms captured by the offer form and editor.
class OfferTerms {
  OfferTerms({
    required this.price,
    this.message = '',
    List<String> imageMediaIds = const [],
    required this.schedule,
    required this.place,
  }) : imageMediaIds = requireNonBlankIds(imageMediaIds, 'imageMediaIds');

  /// Total offered price. Item payment stays offline; this is the agreed
  /// amount shown to both sides.
  final Money price;

  /// Optional seller message.
  final String message;

  /// References to uploaded offer images. Upload itself is storage work.
  final List<String> imageMediaIds;

  /// Proposed local date, time and timezone.
  final LocalSchedule schedule;

  /// Proposed meeting place.
  final MeetingPlace place;

  OfferTerms copyWith({
    Money? price,
    String? message,
    List<String>? imageMediaIds,
    LocalSchedule? schedule,
    MeetingPlace? place,
  }) {
    return OfferTerms(
      price: price ?? this.price,
      message: message ?? this.message,
      imageMediaIds: imageMediaIds ?? this.imageMediaIds,
      schedule: schedule ?? this.schedule,
      place: place ?? this.place,
    );
  }

  /// Advisory checks for the offer form. The server re-validates every value.
  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (!price.isPositive) {
      issues.add(
        const ValidationIssue(
          field: 'price',
          code: ValidationCodes.invalidValue,
          message: 'Enter an offer price greater than zero.',
        ),
      );
    }
    if (message.length > 1000) {
      issues.add(
        const ValidationIssue(
          field: 'message',
          code: ValidationCodes.tooLong,
          message: 'Keep the message within 1000 characters.',
        ),
      );
    }
    return List<ValidationIssue>.unmodifiable(issues);
  }

  @override
  bool operator ==(Object other) =>
      other is OfferTerms &&
      other.price == price &&
      other.message == message &&
      _sameIds(other.imageMediaIds, imageMediaIds) &&
      other.schedule == schedule &&
      other.place == place;

  @override
  int get hashCode => Object.hash(
    price,
    message,
    Object.hashAll(imageMediaIds),
    schedule,
    place,
  );

  static bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'OfferTerms(price: $price, schedule: $schedule, place: $place, '
      'images: ${imageMediaIds.length})';
}

/// One immutable offer revision. [sequence] is server-assigned and increases
/// with each accepted revision.
class OfferRevision {
  OfferRevision({
    required String id,
    required String offerId,
    required this.sequence,
    required this.terms,
    required this.status,
    required String proposedByUserId,
    required DateTime createdAt,
    DateTime? resolvedUtcInstant,
    this.resolvedUtcOffsetMinutes,
  }) : id = requireNonBlank(id, 'id'),
       offerId = requireNonBlank(offerId, 'offerId'),
       proposedByUserId = requireNonBlank(proposedByUserId, 'proposedByUserId'),
       createdAt = createdAt.toUtc(),
       resolvedUtcInstant = resolvedUtcInstant?.toUtc() {
    if (sequence < 1) {
      throw ArgumentError.value(sequence, 'sequence', 'must be at least 1');
    }
  }

  final String id;
  final String offerId;
  final int sequence;
  final OfferTerms terms;
  final OfferRevisionStatus status;
  final String proposedByUserId;
  final DateTime createdAt;

  /// Server-resolved UTC instant for [OfferTerms.schedule], when the backend
  /// provided one. Never derived from the device clock or a fixed offset.
  final DateTime? resolvedUtcInstant;

  /// Server-resolved offset in minutes for the accepted local schedule.
  final int? resolvedUtcOffsetMinutes;

  @override
  String toString() =>
      'OfferRevision($id, offer: $offerId, seq: $sequence, '
      'status: ${status.name})';
}

/// A seller offer with its full revision history.
class Offer {
  Offer({
    required String id,
    required String requestId,
    required String buyerUserId,
    required String sellerProfileId,
    required String sellerUserId,
    required List<OfferRevision> revisions,
    required this.status,
    required this.stamp,
    String? sellerDisplayName,
    this.requestTitle,
    this.acceptedRevisionId,
    this.conversationId,
    this.purchaseSelected = false,
    DateTime? requestFirstAcceptedAt,
    DateTime? requestAcceptanceExpiresAt,
  }) : id = requireNonBlank(id, 'id'),
       requestId = requireNonBlank(requestId, 'requestId'),
       buyerUserId = requireNonBlank(buyerUserId, 'buyerUserId'),
       sellerProfileId = requireNonBlank(sellerProfileId, 'sellerProfileId'),
       sellerUserId = requireNonBlank(sellerUserId, 'sellerUserId'),
       sellerDisplayName = _normalizeDisplayName(sellerDisplayName),
       requestFirstAcceptedAt = requestFirstAcceptedAt?.toUtc(),
       requestAcceptanceExpiresAt = requestAcceptanceExpiresAt?.toUtc(),
       revisions = List<OfferRevision>.unmodifiable(revisions) {
    _validateRevisions();
  }

  static String? _normalizeDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  final String id;
  final String requestId;
  final String buyerUserId;
  final String sellerProfileId;
  final String sellerUserId;

  /// Public seller display name supplied by the server projection, when the
  /// backend exposes it. Never a client-derived identity.
  final String? sellerDisplayName;
  final String? requestTitle;

  /// Ordered by ascending [OfferRevision.sequence].
  final List<OfferRevision> revisions;

  final OfferStatus status;

  /// The buyer-selected revision, or null while none is selected.
  final String? acceptedRevisionId;

  /// Conversation opened for this offer once a seller is selected.
  final String? conversationId;

  /// True when the buyer designated this negotiation as the final purchase.
  /// Only this seller can complete the request PIN.
  final bool purchaseSelected;

  /// Server-owned start of the request acceptance countdown. The first
  /// acceptance starts it; later acceptances never reset it.
  final DateTime? requestFirstAcceptedAt;

  /// Exclusive end of the request acceptance window. Discovery and new offers
  /// close here; an already accepted meeting keeps its own next-local-midnight
  /// cutoff.
  final DateTime? requestAcceptanceExpiresAt;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  OfferRevision get latestRevision => revisions.last;

  OfferRevision? get acceptedRevision {
    final id = acceptedRevisionId;
    if (id == null) return null;
    for (final revision in revisions) {
      if (revision.id == id) return revision;
    }
    return null;
  }

  void _validateRevisions() {
    if (revisions.isEmpty) {
      throw ArgumentError.value(
        revisions,
        'revisions',
        'an offer keeps at least one revision',
      );
    }
    final ids = <String>{};
    var previousSequence = 0;
    for (final revision in revisions) {
      if (revision.offerId != id) {
        throw ArgumentError.value(
          revision.offerId,
          'revisions',
          'revision ${revision.id} belongs to another offer',
        );
      }
      if (!ids.add(revision.id)) {
        throw ArgumentError.value(
          revision.id,
          'revisions',
          'duplicate revision id',
        );
      }
      if (revision.sequence <= previousSequence) {
        throw ArgumentError.value(
          revision.sequence,
          'revisions',
          'revisions must be ordered by ascending sequence',
        );
      }
      previousSequence = revision.sequence;
    }
    final acceptedId = acceptedRevisionId;
    if (acceptedId != null && !ids.contains(acceptedId)) {
      throw ArgumentError.value(
        acceptedId,
        'acceptedRevisionId',
        'must reference a revision of this offer',
      );
    }
  }

  Offer copyWith({
    List<OfferRevision>? revisions,
    OfferStatus? status,
    String? acceptedRevisionId,
    String? conversationId,
    RecordStamp? stamp,
    bool? purchaseSelected,
    DateTime? requestFirstAcceptedAt,
    DateTime? requestAcceptanceExpiresAt,
  }) {
    return Offer(
      id: id,
      requestId: requestId,
      buyerUserId: buyerUserId,
      sellerProfileId: sellerProfileId,
      sellerUserId: sellerUserId,
      sellerDisplayName: sellerDisplayName,
      requestTitle: requestTitle,
      revisions: revisions ?? this.revisions,
      status: status ?? this.status,
      acceptedRevisionId: acceptedRevisionId ?? this.acceptedRevisionId,
      conversationId: conversationId ?? this.conversationId,
      stamp: stamp ?? this.stamp,
      purchaseSelected: purchaseSelected ?? this.purchaseSelected,
      requestFirstAcceptedAt:
          requestFirstAcceptedAt ?? this.requestFirstAcceptedAt,
      requestAcceptanceExpiresAt:
          requestAcceptanceExpiresAt ?? this.requestAcceptanceExpiresAt,
    );
  }

  @override
  String toString() =>
      'Offer($id, request: $requestId, seller: $sellerProfileId, '
      '${status.name}, revisions: ${revisions.length})';
}

/// Submits a new offer with complete terms.
class SubmitOfferCommand {
  SubmitOfferCommand({
    required String requestId,
    required this.terms,
    required String idempotencyKey,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String requestId;
  final OfferTerms terms;
  final String idempotencyKey;
}

/// Replaces all terms of an existing offer at an expected revision.
class ReviseOfferCommand {
  ReviseOfferCommand({
    required String offerId,
    required this.expectedOfferRevision,
    required this.terms,
    required String idempotencyKey,
  }) : offerId = requireNonBlank(offerId, 'offerId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedOfferRevision < 1) {
      throw ArgumentError.value(
        expectedOfferRevision,
        'expectedOfferRevision',
        'must be at least 1',
      );
    }
  }

  final String offerId;
  final int expectedOfferRevision;
  final OfferTerms terms;
  final String idempotencyKey;
}

/// Withdraws an offer the seller no longer stands behind.
class WithdrawOfferCommand {
  WithdrawOfferCommand({
    required String offerId,
    required this.expectedOfferRevision,
    required String idempotencyKey,
    this.reason,
  }) : offerId = requireNonBlank(offerId, 'offerId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedOfferRevision < 1) {
      throw ArgumentError.value(
        expectedOfferRevision,
        'expectedOfferRevision',
        'must be at least 1',
      );
    }
  }

  final String offerId;
  final int expectedOfferRevision;
  final String idempotencyKey;
  final String? reason;
}

/// The buyer selects one offer revision to open the permitted conversation.
///
/// The expected revisions make stale or duplicate selections a typed conflict
/// instead of a silent second acceptance. Several offers may be selected for
/// one request; each keeps its own conversation and meeting.
class SelectOfferCommand {
  SelectOfferCommand({
    required String offerId,
    required String revisionId,
    required this.expectedOfferRevision,
    required String idempotencyKey,
  }) : offerId = requireNonBlank(offerId, 'offerId'),
       revisionId = requireNonBlank(revisionId, 'revisionId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedOfferRevision < 1) {
      throw ArgumentError.value(
        expectedOfferRevision,
        'expectedOfferRevision',
        'must be at least 1',
      );
    }
  }

  final String offerId;
  final String revisionId;
  final int expectedOfferRevision;
  final String idempotencyKey;
}

/// The buyer identifies the accepted seller they purchased from. Only that
/// seller can complete the request PIN; changing the designation is allowed
/// until a purchase is confirmed.
class SelectPurchaseCommand {
  SelectPurchaseCommand({
    required String offerId,
    required this.expectedOfferRevision,
    required String idempotencyKey,
  }) : offerId = requireNonBlank(offerId, 'offerId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedOfferRevision < 1) {
      throw ArgumentError.value(
        expectedOfferRevision,
        'expectedOfferRevision',
        'must be at least 1',
      );
    }
  }

  final String offerId;
  final int expectedOfferRevision;
  final String idempotencyKey;
}
