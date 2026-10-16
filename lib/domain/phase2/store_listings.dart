/// Seller Store listing contracts for Phase 2.
///
/// Store listings are a discovery catalogue, not ecommerce: there is no
/// inventory, checkout, shipping or item payment here. The owner record keeps
/// server-owned publication and moderation state; [PublicStoreListing] is a
/// separate read model without owner identity, moderation state or private
/// contacts and addresses.
///
/// The current editor collects a free-text category and price label. This
/// contract preserves that behavior and does not hardcode catalogue values,
/// pricing policy or plan limits; those stay server-controlled.
library;

import 'common.dart';

enum ListingKind { product, service }

/// Server-owned publication state.
///
/// [archived] replaces a hard delete so historical references survive; the
/// current Store manager "Delete listing" action maps to archiving.
enum ListingStatus { draft, active, paused, archived }

/// Server-owned moderation state. Transitions and policies are unresolved and
/// stay on the server.
enum ListingModerationStatus { pendingReview, approved, rejected }

/// What the seller asked for when saving a listing.
///
/// The server decides the resulting [ListingStatus] and may moderate or reject
/// the publish request.
enum ListingPublishIntent { draft, publish }

/// Owner-facing Store listing record.
class StoreListing {
  StoreListing({
    required String id,
    required String sellerProfileId,
    required String sellerUserId,
    required this.kind,
    required String title,
    this.description = '',
    String? categoryLabel,
    String? categoryId,
    required String priceLabel,
    this.serviceArea = '',
    this.availability = '',
    List<String> imageMediaIds = const [],
    required this.status,
    required this.moderationStatus,
    required this.stamp,
    DateTime? publishedAt,
  }) : id = requireNonBlank(id, 'id'),
       sellerProfileId = requireNonBlank(sellerProfileId, 'sellerProfileId'),
       sellerUserId = requireNonBlank(sellerUserId, 'sellerUserId'),
       title = requireNonBlank(title, 'title'),
       categoryLabel = requireNonBlank(categoryLabel ?? '', 'categoryLabel'),
       categoryId = optionalNonBlank(categoryId, 'categoryId'),
       priceLabel = requireNonBlank(priceLabel, 'priceLabel'),
       imageMediaIds = requireNonBlankIds(imageMediaIds, 'imageMediaIds'),
       publishedAt = publishedAt?.toUtc();

  final String id;

  /// Public seller profile that owns this listing.
  final String sellerProfileId;

  /// Owner auth identity. Never part of a public projection.
  final String sellerUserId;

  final ListingKind kind;
  final String title;
  final String description;

  /// Category display snapshot for history and rendering. A label never
  /// identifies a category; use [categoryId] for identity.
  final String categoryLabel;

  /// Catalogue category id selected for this listing.
  ///
  /// Null only on legacy free-text records created before catalogue binding.
  /// New create/update commands require a category id; a retired category
  /// keeps its id so the listing's history stays readable.
  final String? categoryId;

  /// Free-text price display such as `$650`, `From $50` or `Quote required`.
  /// Structured pricing and commercial rules are not modelled.
  final String priceLabel;

  /// Public approximate pickup/service area label.
  final String serviceArea;

  final String availability;
  final List<String> imageMediaIds;

  /// Server-owned publication state; never set by a client command.
  final ListingStatus status;

  /// Server-owned moderation state.
  final ListingModerationStatus moderationStatus;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  final DateTime? publishedAt;

  bool get isPubliclyVisible =>
      status == ListingStatus.active &&
      moderationStatus == ListingModerationStatus.approved;

  StoreListing copyWith({
    String? title,
    String? description,
    String? categoryLabel,
    String? categoryId,
    String? priceLabel,
    String? serviceArea,
    String? availability,
    List<String>? imageMediaIds,
    ListingStatus? status,
    ListingModerationStatus? moderationStatus,
    RecordStamp? stamp,
    DateTime? publishedAt,
  }) {
    return StoreListing(
      id: id,
      sellerProfileId: sellerProfileId,
      sellerUserId: sellerUserId,
      kind: kind,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      categoryId: categoryId ?? this.categoryId,
      priceLabel: priceLabel ?? this.priceLabel,
      serviceArea: serviceArea ?? this.serviceArea,
      availability: availability ?? this.availability,
      imageMediaIds: imageMediaIds ?? this.imageMediaIds,
      status: status ?? this.status,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      stamp: stamp ?? this.stamp,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }

  /// Buyer-facing projection. Contains no owner auth identity, no publication
  /// or moderation state and no private contacts or addresses.
  PublicStoreListing toPublicProjection() {
    return PublicStoreListing(
      id: id,
      sellerProfileId: sellerProfileId,
      kind: kind,
      title: title,
      description: description,
      categoryLabel: categoryLabel,
      categoryId: categoryId,
      priceLabel: priceLabel,
      serviceArea: serviceArea,
      availability: availability,
      imageMediaIds: imageMediaIds,
      publishedAt: publishedAt,
    );
  }

  @override
  String toString() =>
      'StoreListing($id, ${kind.name}, ${status.name}, '
      'moderation: ${moderationStatus.name})';
}

/// Buyer-facing listing projection for discovery and public store previews.
///
/// The server only builds this for listings that are published and approved.
class PublicStoreListing {
  PublicStoreListing({
    required String id,
    required String sellerProfileId,
    required this.kind,
    required String title,
    this.description = '',
    String? categoryLabel,
    String? categoryId,
    required String priceLabel,
    this.serviceArea = '',
    this.availability = '',
    List<String> imageMediaIds = const [],
    DateTime? publishedAt,
  }) : id = requireNonBlank(id, 'id'),
       sellerProfileId = requireNonBlank(sellerProfileId, 'sellerProfileId'),
       title = requireNonBlank(title, 'title'),
       categoryLabel = requireNonBlank(categoryLabel ?? '', 'categoryLabel'),
       categoryId = optionalNonBlank(categoryId, 'categoryId'),
       priceLabel = requireNonBlank(priceLabel, 'priceLabel'),
       imageMediaIds = requireNonBlankIds(imageMediaIds, 'imageMediaIds'),
       publishedAt = publishedAt?.toUtc();

  final String id;
  final String sellerProfileId;
  final ListingKind kind;
  final String title;
  final String description;

  /// Category display label. Not an identity.
  final String categoryLabel;

  /// Catalogue category id, or null for legacy free-text records.
  final String? categoryId;

  final String priceLabel;
  final String serviceArea;
  final String availability;
  final List<String> imageMediaIds;
  final DateTime? publishedAt;

  @override
  String toString() =>
      'PublicStoreListing($id, ${kind.name}, seller: $sellerProfileId)';
}

/// Server-derived counts for the Store manager summary card.
///
/// Counts come from the backend so paginated reads do not have to be
/// aggregated on the client.
class StoreListingSummary {
  StoreListingSummary({
    this.draftCount = 0,
    this.activeCount = 0,
    this.pausedCount = 0,
    this.archivedCount = 0,
  }) {
    if (draftCount < 0 ||
        activeCount < 0 ||
        pausedCount < 0 ||
        archivedCount < 0) {
      throw ArgumentError('store summary counts must not be negative');
    }
  }

  final int draftCount;
  final int activeCount;
  final int pausedCount;
  final int archivedCount;

  int get totalCount => draftCount + activeCount + pausedCount + archivedCount;

  @override
  String toString() =>
      'StoreListingSummary(active: $activeCount, total: $totalCount)';
}

/// Creates a listing from complete editable values.
///
/// [categoryId] is the authoritative catalogue selection. The server validates
/// that the category exists, is active for a new selection, and matches
/// [kind]; it resolves the display label itself. Labels are never sent as
/// identity.
///
/// The server owns the new id, the resulting status, moderation and the plan
/// limit check; a plan limit returns [LimitExceededError].
class CreateStoreListingCommand {
  CreateStoreListingCommand({
    required this.kind,
    required String title,
    this.description = '',
    required String categoryId,
    required String priceLabel,
    this.serviceArea = '',
    this.availability = '',
    List<String> imageMediaIds = const [],
    this.publishIntent = ListingPublishIntent.draft,
    required String idempotencyKey,
  }) : title = requireNonBlank(title, 'title'),
       categoryId = requireNonBlank(categoryId, 'categoryId'),
       priceLabel = requireNonBlank(priceLabel, 'priceLabel'),
       imageMediaIds = requireNonBlankIds(imageMediaIds, 'imageMediaIds'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final ListingKind kind;
  final String title;
  final String description;
  final String categoryId;
  final String priceLabel;
  final String serviceArea;
  final String availability;
  final List<String> imageMediaIds;

  /// Draft save or publish request; the server decides the final status.
  final ListingPublishIntent publishIntent;

  final String idempotencyKey;
}

/// Replaces all editable listing values at an expected revision.
///
/// The listing kind is fixed after creation, matching the current editor.
/// [categoryId] is required and revalidated against the catalogue for the
/// listing's kind; the server resolves the display label.
class UpdateStoreListingCommand {
  UpdateStoreListingCommand({
    required String listingId,
    required this.expectedRevision,
    required String title,
    this.description = '',
    required String categoryId,
    required String priceLabel,
    this.serviceArea = '',
    this.availability = '',
    List<String> imageMediaIds = const [],
    required String idempotencyKey,
  }) : listingId = requireNonBlank(listingId, 'listingId'),
       title = requireNonBlank(title, 'title'),
       categoryId = requireNonBlank(categoryId, 'categoryId'),
       priceLabel = requireNonBlank(priceLabel, 'priceLabel'),
       imageMediaIds = requireNonBlankIds(imageMediaIds, 'imageMediaIds'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String listingId;
  final int expectedRevision;
  final String title;
  final String description;
  final String categoryId;
  final String priceLabel;
  final String serviceArea;
  final String availability;
  final List<String> imageMediaIds;
  final String idempotencyKey;
}

/// Publishes or pauses a listing. The server owns the resulting status,
/// moderation and plan-limit checks.
class SetStoreListingPublicationCommand {
  SetStoreListingPublicationCommand({
    required String listingId,
    required this.expectedRevision,
    required this.publish,
    required String idempotencyKey,
  }) : listingId = requireNonBlank(listingId, 'listingId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String listingId;
  final int expectedRevision;
  final bool publish;
  final String idempotencyKey;
}

/// Archives a listing so it disappears from the manager without losing its
/// history. The current "Delete listing" action maps to this command.
class ArchiveStoreListingCommand {
  ArchiveStoreListingCommand({
    required String listingId,
    required this.expectedRevision,
    required String idempotencyKey,
    this.reason,
  }) : listingId = requireNonBlank(listingId, 'listingId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String listingId;
  final int expectedRevision;
  final String idempotencyKey;
  final String? reason;
}

/// Creates a draft copy of an existing listing.
///
/// The server owns the new id, the copied revision and the plan-limit check.
class DuplicateStoreListingCommand {
  DuplicateStoreListingCommand({
    required String listingId,
    required String idempotencyKey,
  }) : listingId = requireNonBlank(listingId, 'listingId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final String listingId;
  final String idempotencyKey;
}
