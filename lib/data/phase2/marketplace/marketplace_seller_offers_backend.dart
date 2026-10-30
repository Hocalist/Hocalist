/// Real-mode seller offers backend: own-offer history reads and withdrawal.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/offers.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

class Phase2MarketplaceSellerOffersBackend
    implements
        MarketplaceSellerOffersBackend,
        MarketplaceSellerOffersRevisionBackend {
  Phase2MarketplaceSellerOffersBackend({
    required this.adapter,
    required this.sellerUserId,
  });

  final MarketplaceDataAdapter adapter;
  final String sellerUserId;

  @override
  Future<List<Offer>> loadSellerOffers() async {
    final offers = <Offer>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await adapter.fetchSellerOffers(
        sellerUserId: sellerUserId,
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
  Future<Offer> withdrawOffer({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) async {
    final result = await adapter.withdrawOffer(
      WithdrawOfferCommand(
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

  @override
  Future<Offer> reviseOffer({
    required String offerId,
    required int expectedOfferRevision,
    required OfferTerms terms,
    required String operationKey,
  }) async {
    final result = await adapter.reviseOffer(
      ReviseOfferCommand(
        offerId: offerId,
        expectedOfferRevision: expectedOfferRevision,
        terms: terms,
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
      return 'Your offer change could not be saved. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.permissionDenied => 'You cannot change this offer.',
      RepositoryFailureKind.notFound => 'This offer is no longer available.',
      RepositoryFailureKind.conflict =>
        'This offer changed. Please try again.',
      RepositoryFailureKind.network =>
        'The change could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.validation =>
        'This offer can no longer be withdrawn.',
      _ => 'Your offer change could not be saved. Try again.',
    };
  }
}
