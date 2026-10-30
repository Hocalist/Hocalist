/// Real-mode Store backend for the approved seller Store screen.
///
/// Bridges the screen's local Store model to the marketplace RPCs. The screen
/// keeps its approved layout; this adapter owns mapping, category identity and
/// user-safe error messages. Plan limits, moderation and ownership remain
/// server decisions.
///
/// Revision contract: the authoritative revision travels record -> editor ->
/// command. The adapter never refreshes the expected revision to force a
/// write; a stale editor produces a conflict instead of overwriting another
/// device's newer edit.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/store_listings.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

class Phase2MarketplaceStoreBackend implements MarketplaceStoreBackend {
  Phase2MarketplaceStoreBackend({
    required this.adapter,
    required this.sellerUserId,
  });

  final MarketplaceDataAdapter adapter;
  final String sellerUserId;

  @override
  Future<List<LocalStoreListing>> loadListings() async {
    final result = await adapter.fetchSellerListings(
      sellerUserId: sellerUserId,
    );
    if (result.isFailure) {
      throw StoreBackendException(
        _message(result.errorOrNull),
        ambiguous: _isAmbiguous(result.errorOrNull),
      );
    }
    return result.valueOrNull!.items
        .where((listing) => listing.status != ListingStatus.archived)
        .map(_toLocal)
        .toList(growable: false);
  }

  @override
  Future<List<StoreCategoryOption>> loadCategories() async {
    final options = <StoreCategoryOption>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await adapter.fetchCategories(
        includeRetired: true,
        page: PageQuery(limit: 200, cursor: cursor),
      );
      if (result.isFailure) {
        throw StoreBackendException(
          _message(result.errorOrNull),
          ambiguous: _isAmbiguous(result.errorOrNull),
        );
      }
      final slice = result.valueOrNull!;
      for (final category in slice.items) {
        options.add(
          StoreCategoryOption(
            id: category.id,
            label: category.label,
            scope: category.scope.name,
            status: category.status.name,
          ),
        );
      }
      cursor = slice.nextCursor;
      if (cursor == null) break;
    }
    return options;
  }

  @override
  Future<StoreWriteResult> saveListing(
    LocalStoreListing listing, {
    required String operationKey,
  }) async {
    final categoryId = listing.categoryId;
    if (categoryId == null || categoryId.isEmpty) {
      throw const StoreBackendException(
        'Choose a category from the current catalogue.',
      );
    }
    if (listing.id.isEmpty || listing.id.startsWith('pending-')) {
      final result = await adapter.createStoreListing(
        CreateStoreListingCommand(
          kind: _kind(listing.kind),
          title: listing.title,
          description: listing.description,
          categoryId: categoryId,
          categoryAnswers: listing.categoryAnswers,
          priceLabel: listing.priceLabel,
          serviceArea: listing.serviceArea,
          availability: listing.availability,
          imageMediaIds: listing.imageMediaIds,
          publishIntent: listing.status == LocalListingStatus.active
              ? ListingPublishIntent.publish
              : ListingPublishIntent.draft,
          idempotencyKey: operationKey,
        ),
      );
      return StoreWriteResult(listing: _require(result));
    }

    if (listing.revision < 1) {
      throw const StoreBackendException(
        'Refresh your Store before saving this listing.',
      );
    }
    final update = await adapter.updateStoreListing(
      UpdateStoreListingCommand(
        listingId: listing.id,
        expectedRevision: listing.revision,
        title: listing.title,
        description: listing.description,
        categoryId: categoryId,
        categoryAnswers: listing.categoryAnswers,
        priceLabel: listing.priceLabel,
        serviceArea: listing.serviceArea,
        availability: listing.availability,
        imageMediaIds: listing.imageMediaIds,
        idempotencyKey: operationKey,
      ),
    );
    if (update.isFailure) {
      final error = update.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    final saved = update.valueOrNull!;
    final desiredActive = listing.status == LocalListingStatus.active;
    final remoteActive = saved.status == ListingStatus.active;
    if (desiredActive == remoteActive) {
      return StoreWriteResult(listing: _toLocal(saved));
    }
    final publication = await adapter.setStoreListingPublication(
      SetStoreListingPublicationCommand(
        listingId: saved.id,
        expectedRevision: saved.stamp.revision,
        publish: desiredActive,
        idempotencyKey: '$operationKey-publish',
      ),
    );
    if (publication.isFailure) {
      final error = publication.errorOrNull!;
      if (_isAmbiguous(error)) {
        throw StoreBackendException(_message(error), ambiguous: true);
      }
      return StoreWriteResult(
        listing: _toLocal(saved),
        warning:
            'Saved, but the publication change could not be applied. ${_message(error)}',
      );
    }
    return StoreWriteResult(listing: _toLocal(publication.valueOrNull!));
  }

  @override
  Future<StoreWriteResult> setListingStatus(
    String listingId,
    LocalListingStatus status, {
    required String operationKey,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1) {
      throw const StoreBackendException(
        'Open your Store again before changing this listing.',
      );
    }
    final result = await adapter.setStoreListingPublication(
      SetStoreListingPublicationCommand(
        listingId: listingId,
        expectedRevision: expectedRevision,
        publish: status == LocalListingStatus.active,
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
    return StoreWriteResult(listing: _toLocal(result.valueOrNull!));
  }

  @override
  Future<StoreWriteResult> duplicateListing(
    String listingId, {
    required String operationKey,
  }) async {
    final result = await adapter.duplicateStoreListing(
      DuplicateStoreListingCommand(
        listingId: listingId,
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
    return StoreWriteResult(listing: _toLocal(result.valueOrNull!));
  }

  @override
  Future<void> archiveListing(
    String listingId, {
    required String operationKey,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1) {
      throw const StoreBackendException(
        'Open your Store again before deleting this listing.',
      );
    }
    final result = await adapter.archiveStoreListing(
      ArchiveStoreListingCommand(
        listingId: listingId,
        expectedRevision: expectedRevision,
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
  }

  LocalStoreListing _require(RepositoryResult<StoreListing> result) {
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return _toLocal(result.valueOrNull!);
  }

  LocalStoreListing _toLocal(StoreListing listing) {
    return LocalStoreListing(
      id: listing.id,
      kind: listing.kind == ListingKind.product
          ? LocalListingKind.product
          : LocalListingKind.service,
      title: listing.title,
      priceLabel: listing.priceLabel,
      description: listing.description,
      category: listing.categoryLabel,
      categoryId: listing.categoryId,
      categoryAnswers: listing.categoryAnswers,
      serviceArea: listing.serviceArea,
      availability: listing.availability,
      revision: listing.stamp.revision,
      pendingReview:
          listing.moderationStatus == ListingModerationStatus.pendingReview,
      rejected: listing.moderationStatus == ListingModerationStatus.rejected,
      status: switch (listing.status) {
        ListingStatus.active => LocalListingStatus.active,
        ListingStatus.paused => LocalListingStatus.paused,
        ListingStatus.draft ||
        ListingStatus.archived => LocalListingStatus.draft,
      },
      imageAsset: null,
      imageCount: listing.imageMediaIds.length,
      imageMediaIds: List.unmodifiable(listing.imageMediaIds),
    );
  }

  ListingKind _kind(LocalListingKind kind) => kind == LocalListingKind.product
      ? ListingKind.product
      : ListingKind.service;

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
      return 'Your Store change could not be saved. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.limitExceeded =>
        'Your plan Store limit was reached.',
      RepositoryFailureKind.permissionDenied =>
        'You do not have access to that Store action.',
      RepositoryFailureKind.network =>
        'The change could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.conflict =>
        'The listing changed on another device. Please try again.',
      RepositoryFailureKind.validation =>
        'Check the listing details and try again.',
      _ => 'Your Store change could not be saved. Try again.',
    };
  }
}
