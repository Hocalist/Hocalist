/// Real-mode buyer offers backend: per-request offer reads and selection.
///
/// Bridges the buyer offers list/detail screens to the marketplace RPCs. The
/// server owns eligibility, acceptance policy and conversation opening; this
/// adapter only maps identifiers, pages and user-safe errors.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/offers.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

class Phase2MarketplaceBuyerOffersBackend
    implements MarketplaceBuyerOffersBackend {
  Phase2MarketplaceBuyerOffersBackend({required this.adapter});

  final MarketplaceDataAdapter adapter;

  @override
  Future<List<Offer>> loadRequestOffers(String requestId) async {
    final offers = <Offer>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await adapter.fetchRequestOffers(
        requestId: requestId,
        page: PageQuery(limit: 50, cursor: cursor),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        throw StoreBackendException(
          _message(error),
          ambiguous: _isAmbiguous(error),
        );
      }
      final slice = result.valueOrNull!;
      offers.addAll(slice.items);
      cursor = slice.nextCursor;
      if (cursor == null) break;
    }
    return offers;
  }

  @override
  Future<OfferSelectionOutcome> selectOffer({
    required String offerId,
    required String revisionId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final result = await adapter.selectOffer(
      SelectOfferCommand(
        offerId: offerId,
        revisionId: revisionId,
        expectedOfferRevision: expectedOfferRevision,
        idempotencyKey: operationKey,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    final selected = result.valueOrNull!;
    if (selected.conversationId != null) {
      return OfferSelectionOutcome(
        offer: selected,
        conversationId: selected.conversationId,
      );
    }
    // Selection is committed; opening is the server-authorized second step.
    // A failure here leaves the selection intact and is reported as uncertain
    // so the caller retries the same key instead of re-selecting.
    final opened = await adapter.openOfferConversation(
      offerId: selected.id,
      idempotencyKey: '$operationKey-open',
    );
    if (opened.isFailure) {
      final error = opened.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return OfferSelectionOutcome(
      offer: selected,
      conversationId: opened.valueOrNull,
    );
  }

  @override
  Future<Offer> selectPurchaseSeller({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final result = await adapter.selectPurchaseOffer(
      SelectPurchaseCommand(
        offerId: offerId,
        expectedOfferRevision: expectedOfferRevision,
        idempotencyKey: operationKey,
      ),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  /// An outcome that may have committed despite the reported failure. These
  /// must be retried with the same operation key and payload.
  bool _isAmbiguous(RepositoryError? error) {
    if (error == null) return false;
    return switch (error.kind) {
      RepositoryFailureKind.network ||
      RepositoryFailureKind.malformedResponse => true,
      RepositoryFailureKind.server =>
        error is ServerError &&
            (error.statusCode == null || error.statusCode! >= 500),
      _ => false,
    };
  }

  String _message(RepositoryError? error) {
    if (error == null) {
      return 'The offer could not be selected. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.permissionDenied => 'You cannot select this offer.',
      RepositoryFailureKind.notFound => 'This offer is no longer available.',
      RepositoryFailureKind.conflict =>
        'This offer changed. Open the list again and try again.',
      RepositoryFailureKind.network =>
        'The selection could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.validation =>
        'This offer can no longer be selected.',
      _ => 'The offer could not be selected. Try again.',
    };
  }
}
