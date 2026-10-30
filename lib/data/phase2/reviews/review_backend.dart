/// Post-purchase review adapter and page-facing backend.
///
/// Eligibility, submission, update and the public aggregate all come from the
/// reviewed `review_*` RPCs. A retry with the same intent key and payload
/// returns the stored review instead of creating a second one.
library;

import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/reviews.dart';
import '../../local_marketplace_repository.dart';
import '../marketplace/marketplace_codecs.dart';
import '../marketplace/marketplace_error_mapper.dart';
import '../marketplace/marketplace_session.dart';
import '../marketplace/marketplace_transport.dart';

class ReviewDecodeException implements Exception {
  const ReviewDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'ReviewDecodeException($detail)';
}

/// Page-facing review seam. Implementations never fabricate a rating or count.
abstract interface class ReviewBackend {
  Future<ReviewEligibilityView> loadEligibility(String requestId);

  Future<OutcomeReview> submitReview(SubmitReviewCommand command);

  Future<OutcomeReview> updateReview(UpdateReviewCommand command);

  Future<PublicSellerReputation> loadReputation(String sellerProfileId);
}

class ReviewDataAdapter {
  static List<String> _images(Map<String, Object?> row, String context) {
    final value = row['image_media_ids'];
    if (value == null) return const [];
    if (value is! List ||
        value.length > 4 ||
        value.any((id) => id is! String || id.trim().isEmpty) ||
        value.toSet().length != value.length) {
      throw ReviewDecodeException('$context.image_media_ids');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  ReviewDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  static const String schema = 'hocalist';

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  Future<RepositoryResult<Map<String, Object?>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = session.currentUserId;
    if (userId == null) return const RepositoryFailureResult(_unauthenticated);
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: schema, function: function, params: params),
    );
    if (session.currentUserId != userId) {
      return const RepositoryFailureResult(_staleSession);
    }
    return switch (response) {
      MarketplaceTransportData(:final data) => _decode(function, data),
      MarketplaceTransportError() => RepositoryFailureResult(
        errorMapper.map(response, operation: function),
      ),
    };
  }

  RepositoryResult<Map<String, Object?>> _decode(
    String function,
    Object? data,
  ) {
    try {
      return RepositorySuccess(decodeObject(data, function));
    } on MarketplaceDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<T>> _read<T>(
    String function,
    Map<String, Object?> params,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, params);
    if (result.isFailure) return RepositoryFailureResult(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, function));
    } on ReviewDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    } on MarketplaceDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<T>> _keyedCommand<T>(
    String function,
    String key,
    Map<String, Object?> input,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, {'p_key': key, 'p_input': input});
    if (result.isFailure) return RepositoryFailureResult(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, function));
    } on ReviewDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<ReviewEligibilityView>> fetchEligibility(
    String requestId,
  ) => _read('review_status', {'p_request': requestId}, _decodeEligibility);

  Future<RepositoryResult<OutcomeReview>> submit(SubmitReviewCommand command) =>
      _keyedCommand('review_submit', command.idempotencyKey, {
        'request_id': command.requestId,
        'rating': command.rating,
        'body': command.body,
        if (command.imageMediaIds.isNotEmpty)
          'image_media_ids': command.imageMediaIds,
      }, _decodeReview);

  Future<RepositoryResult<OutcomeReview>> update(UpdateReviewCommand command) =>
      _keyedCommand('review_update', command.idempotencyKey, {
        'review_id': command.reviewId,
        'expected_revision': command.expectedRevision,
        'rating': command.rating,
        'body': command.body,
        if (command.imageMediaIds != null)
          'image_media_ids': command.imageMediaIds,
      }, _decodeReview);

  Future<RepositoryResult<PublicSellerReputation>> fetchReputation(
    String sellerProfileId,
  ) => _read('seller_public_reputation', {
    'p_seller_profile': sellerProfileId,
  }, _decodeReputation);

  OutcomeReview _decodeReview(Map<String, Object?> row, String context) {
    final id = row['id'];
    final requestId = row['request_id'];
    final rating = row['rating'];
    final body = row['body'];
    final status = row['status'];
    final revision = row['revision'];
    final createdAt = row['created_at'];
    final updatedAt = row['updated_at'];
    final decodedStatus = status is String
        ? ReviewModerationState.fromWire(status)
        : null;
    if (id is! String ||
        requestId is! String ||
        rating is! int ||
        body is! String ||
        decodedStatus == null ||
        revision is! int ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null) {
      throw ReviewDecodeException(context);
    }
    return OutcomeReview(
      id: id,
      requestId: requestId,
      rating: rating,
      body: body,
      imageMediaIds: _images(row, context),
      status: decodedStatus,
      revision: revision,
      createdAt: DateTime.parse(createdAt),
      updatedAt: updatedAt is String ? DateTime.tryParse(updatedAt) : null,
      moderationReason: row['moderation_reason'] is String
          ? row['moderation_reason']! as String
          : null,
    );
  }

  ReviewEligibilityView _decodeEligibility(
    Map<String, Object?> row,
    String context,
  ) {
    final requestId = row['request_id'];
    final eligible = row['eligible'];
    final reason = row['reason'];
    if (requestId is! String || eligible is! bool || reason is! String) {
      throw ReviewDecodeException(context);
    }
    final review = row['review'];
    return ReviewEligibilityView(
      requestId: requestId,
      eligible: eligible,
      reason: reason,
      outcomeId: row['outcome_id'] is String
          ? row['outcome_id']! as String
          : null,
      review: review is Map
          ? _decodeReview(Map<String, Object?>.from(review), '$context.review')
          : null,
    );
  }

  PublicSellerReputation _decodeReputation(
    Map<String, Object?> row,
    String context,
  ) {
    final profileId = row['seller_profile_id'];
    final sum = row['rating_sum'];
    final count = row['rating_count'];
    final deals = row['completed_deals'];
    if (profileId is! String || sum is! int || count is! int || deals is! int) {
      throw ReviewDecodeException(context);
    }
    final available = row['available'];
    if (available != null && available is! bool) {
      throw ReviewDecodeException('$context.available');
    }
    final reason = row['reason'];
    if (reason != null && reason is! String) {
      throw ReviewDecodeException('$context.reason');
    }
    final reviewRows = decodeObjectList(row['reviews'], context);
    final reviews = <PublicReviewExcerpt>[];
    for (var index = 0; index < reviewRows.length; index++) {
      final entry = reviewRows[index];
      final entryContext = '$context.reviews[$index]';
      final id = entry['id'];
      final rating = entry['rating'];
      final body = entry['body'];
      final label = entry['reviewer_label'];
      final createdAt = entry['created_at'];
      if (id is! String ||
          rating is! int ||
          body is! String ||
          label is! String ||
          createdAt is! String ||
          DateTime.tryParse(createdAt) == null) {
        throw ReviewDecodeException(entryContext);
      }
      reviews.add(
        PublicReviewExcerpt(
          id: id,
          rating: rating,
          body: body,
          imageMediaIds: _images(entry, entryContext),
          reviewerLabel: label,
          createdAt: DateTime.parse(createdAt).toUtc(),
        ),
      );
    }
    return PublicSellerReputation(
      sellerProfileId: profileId,
      ratingSum: sum,
      ratingCount: count,
      completedDeals: deals,
      reviews: reviews,
      available: available != false,
      withheldReason: reason as String?,
    );
  }
}

class Phase2ReviewBackend implements ReviewBackend {
  Phase2ReviewBackend({required this.adapter});

  final ReviewDataAdapter adapter;

  @override
  Future<ReviewEligibilityView> loadEligibility(String requestId) async {
    final result = await adapter.fetchEligibility(requestId);
    if (result.isFailure) {
      throw _exception(result.errorOrNull!, 'review eligibility');
    }
    return result.valueOrNull!;
  }

  @override
  Future<OutcomeReview> submitReview(SubmitReviewCommand command) async {
    final result = await adapter.submit(command);
    if (result.isFailure) {
      throw _exception(result.errorOrNull!, 'review', code: 'review_submit');
    }
    return result.valueOrNull!;
  }

  @override
  Future<OutcomeReview> updateReview(UpdateReviewCommand command) async {
    final result = await adapter.update(command);
    if (result.isFailure) {
      throw _exception(result.errorOrNull!, 'review', code: 'review_update');
    }
    return result.valueOrNull!;
  }

  @override
  Future<PublicSellerReputation> loadReputation(String sellerProfileId) async {
    final result = await adapter.fetchReputation(sellerProfileId);
    if (result.isFailure) {
      throw _exception(result.errorOrNull!, 'seller reputation');
    }
    return result.valueOrNull!;
  }

  StoreBackendException _exception(
    RepositoryError error,
    String scope, {
    String? code,
  }) => StoreBackendException(
    switch (error.kind) {
      RepositoryFailureKind.network => 'Check your connection and try again.',
      RepositoryFailureKind.permissionDenied =>
        'This $scope action is not available for your account.',
      RepositoryFailureKind.notFound => 'This $scope is no longer available.',
      RepositoryFailureKind.conflict =>
        'That $scope conflicts with a newer server state. Please try again.',
      _ => 'Could not save the $scope. Try again.',
    },
    ambiguous:
        error.kind == RepositoryFailureKind.network ||
        error.kind == RepositoryFailureKind.server ||
        error.kind == RepositoryFailureKind.malformedResponse,
    code: code,
  );
}
