/// Post-purchase review contracts.
///
/// A review is authoritative once the server has a confirmed purchase outcome
/// for the request. One review exists per eligible outcome; submission and
/// update carry a client-owned intent key so a retry never duplicates the
/// review. Moderation is a recorded server decision, and the public aggregate
/// only includes published reviews.
library;

import 'common.dart';

/// Lifecycle state of one review.
enum ReviewModerationState {
  published('published'),
  hidden('hidden'),
  removed('removed');

  const ReviewModerationState(this.wire);

  final String wire;

  static ReviewModerationState? fromWire(String wire) {
    for (final value in ReviewModerationState.values) {
      if (value.wire == wire) return value;
    }
    return null;
  }

  bool get isPublic => this == published;
}

/// One stored review.
class OutcomeReview {
  OutcomeReview({
    required String id,
    required String requestId,
    required this.rating,
    this.body = '',
    required this.status,
    required this.revision,
    required DateTime createdAt,
    DateTime? updatedAt,
    this.moderationReason,
  }) : id = requireNonBlank(id, 'id'),
       requestId = requireNonBlank(requestId, 'requestId'),
       createdAt = createdAt.toUtc(),
       updatedAt = (updatedAt ?? createdAt).toUtc() {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'must be between 1 and 5');
    }
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final String id;
  final String requestId;
  final int rating;
  final String body;
  final ReviewModerationState status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? moderationReason;

  bool get isPublished => status.isPublic;
}

/// Buyer eligibility and their existing review, if any.
class ReviewEligibilityView {
  const ReviewEligibilityView({
    required this.requestId,
    required this.eligible,
    required this.reason,
    this.outcomeId,
    this.review,
  });

  final String requestId;
  final bool eligible;

  /// `confirmed_purchase`, `not_confirmed` or `not_participant`.
  final String reason;
  final String? outcomeId;
  final OutcomeReview? review;

  bool get hasReview => review != null;
}

/// Creates the buyer's authoritative review for a confirmed purchase.
class SubmitReviewCommand {
  SubmitReviewCommand({
    required String requestId,
    required this.rating,
    this.body = '',
    required String idempotencyKey,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'must be between 1 and 5');
    }
    if (body.length > 1500) {
      throw ArgumentError.value(body.length, 'body', 'must be at most 1500');
    }
  }

  final String requestId;
  final int rating;
  final String body;
  final String idempotencyKey;
}

/// Updates the buyer's own review at its expected revision.
class UpdateReviewCommand {
  UpdateReviewCommand({
    required String reviewId,
    required this.expectedRevision,
    required this.rating,
    this.body = '',
    required String idempotencyKey,
  }) : reviewId = requireNonBlank(reviewId, 'reviewId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'must be between 1 and 5');
    }
    if (body.length > 1500) {
      throw ArgumentError.value(body.length, 'body', 'must be at most 1500');
    }
  }

  final String reviewId;
  final int expectedRevision;
  final int rating;
  final String body;
  final String idempotencyKey;
}

/// One published review excerpt in the public seller reputation.
class PublicReviewExcerpt {
  const PublicReviewExcerpt({
    required this.id,
    required this.rating,
    this.body = '',
    required this.reviewerLabel,
    required this.createdAt,
  });

  final String id;
  final int rating;
  final String body;

  /// Masked label (`Hocalist buyer`) until the buyer opts in.
  final String reviewerLabel;
  final DateTime createdAt;
}

/// Server-derived public seller reputation. Only published reviews count.
class PublicSellerReputation {
  PublicSellerReputation({
    required String sellerProfileId,
    required this.ratingSum,
    required this.ratingCount,
    required this.completedDeals,
    List<PublicReviewExcerpt> reviews = const [],
    this.available = true,
    this.withheldReason,
  }) : sellerProfileId = requireNonBlank(sellerProfileId, 'sellerProfileId'),
       reviews = List<PublicReviewExcerpt>.unmodifiable(reviews) {
    if (ratingSum < 0 || ratingCount < 0 || completedDeals < 0) {
      throw ArgumentError('reputation counters must not be negative');
    }
    if (ratingCount == 0 && ratingSum != 0) {
      throw ArgumentError('ratingSum requires at least one rating');
    }
  }

  final String sellerProfileId;
  final int ratingSum;
  final int ratingCount;
  final int completedDeals;
  final List<PublicReviewExcerpt> reviews;

  /// False when the server withheld the projection (for example a restricted
  /// or unknown seller). Aggregates are zero in that state.
  final bool available;

  /// `target_unavailable` or `profile_not_found` when withheld.
  final String? withheldReason;

  double? get averageRating =>
      ratingCount == 0 ? null : ratingSum / ratingCount;
}
