/// Real-mode offers backend for the approved seller offer form.
library;

import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/offers.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

class Phase2MarketplaceOffersBackend implements MarketplaceOffersBackend {
  Phase2MarketplaceOffersBackend({required this.adapter});

  final MarketplaceDataAdapter adapter;

  @override
  Future<List<String>> loadTimezones() async {
    final result = await adapter.fetchTimezones();
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  @override
  Future<Offer> submitOffer({
    required String requestId,
    required OfferTerms terms,
    required String operationKey,
  }) async {
    final result = await adapter.submitOffer(
      SubmitOfferCommand(
        requestId: requestId,
        terms: terms,
        idempotencyKey: operationKey,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
        code: _code(error),
      );
    }
    return result.valueOrNull!;
  }

  String? _code(RepositoryError error) {
    if (error is ValidationError) {
      for (final issue in error.issues) {
        if (issue.code == 'ambiguous_local_time' ||
            issue.code == 'nonexistent_local_time') {
          return issue.code;
        }
      }
    }
    return null;
  }

  bool _isAmbiguous(RepositoryError error) => switch (error.kind) {
    RepositoryFailureKind.network ||
    RepositoryFailureKind.malformedResponse => true,
    RepositoryFailureKind.server =>
      error is ServerError &&
          (error.statusCode == null || error.statusCode! >= 500),
    _ => false,
  };

  String _message(RepositoryError error) => switch (error.kind) {
    RepositoryFailureKind.limitExceeded =>
      error is LimitExceededError && error.limitCode == 'weekly_targets'
          ? 'You reached your weekly targeting limit. Try again next week.'
          : 'Your plan limit was reached.',
    RepositoryFailureKind.permissionDenied =>
      'You cannot offer on this request.',
    RepositoryFailureKind.network =>
      'The offer could not be confirmed. Retry to check it safely.',
    RepositoryFailureKind.conflict => switch (error) {
      ConflictError(conflictCode: 'targeting_fee_unconfigured') =>
        'Targeting is not configured yet, so this offer cannot be accepted. '
            'No charge was made.',
      ConflictError(conflictCode: 'insufficient_single_batch') =>
        'Your prepaid credits cannot cover this interaction. '
            'Add credits before targeting this customer.',
      _ => 'This request changed. Refresh and try again.',
    },
    RepositoryFailureKind.validation =>
      error is ValidationError && error.issues.isNotEmpty
          ? error.issues.first.message
          : 'Check the offer details and try again.',
    _ => 'The offer could not be sent. Try again.',
  };
}
