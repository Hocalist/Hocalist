import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final stamp = RecordStamp(
    revision: 3,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 3),
  );

  StoreListing fullListing({
    ListingStatus status = ListingStatus.active,
    ListingModerationStatus moderation = ListingModerationStatus.approved,
  }) {
    return StoreListing(
      id: 'listing-1',
      sellerProfileId: 'seller-1',
      sellerUserId: 'auth-seller-sentinel',
      kind: ListingKind.product,
      title: 'iPad Air 5th Gen 64GB',
      description: 'Excellent condition with charger included.',
      categoryLabel: 'Electronics',
      categoryId: 'category-tablets',
      priceLabel: r'$650',
      serviceArea: 'Yonkers, NY',
      availability: 'Available today',
      imageMediaIds: const ['media-1', 'media-2'],
      status: status,
      moderationStatus: moderation,
      stamp: stamp,
      publishedAt: DateTime.utc(2026, 5, 2),
    );
  }

  group('StoreListing', () {
    test('keeps every editable and server-owned field', () {
      final listing = fullListing();

      expect(listing.sellerProfileId, 'seller-1');
      expect(listing.sellerUserId, 'auth-seller-sentinel');
      expect(listing.kind, ListingKind.product);
      expect(listing.title, 'iPad Air 5th Gen 64GB');
      expect(listing.description, contains('charger'));
      expect(listing.categoryLabel, 'Electronics');
      expect(listing.categoryId, 'category-tablets');
      expect(listing.priceLabel, r'$650');
      expect(listing.serviceArea, 'Yonkers, NY');
      expect(listing.availability, 'Available today');
      expect(listing.imageMediaIds, ['media-1', 'media-2']);
      expect(listing.status, ListingStatus.active);
      expect(listing.moderationStatus, ListingModerationStatus.approved);
      expect(listing.publishedAt?.isUtc, isTrue);
    });

    test('copyWith preserves untouched values and immutable images', () {
      final listing = fullListing();
      final updated = listing.copyWith(
        title: 'iPad Air 5th Gen 128GB',
        priceLabel: r'$720',
      );

      expect(updated.title, 'iPad Air 5th Gen 128GB');
      expect(updated.priceLabel, r'$720');
      expect(updated.description, listing.description);
      expect(updated.categoryLabel, listing.categoryLabel);
      expect(updated.categoryId, listing.categoryId);
      expect(updated.serviceArea, listing.serviceArea);
      expect(updated.availability, listing.availability);
      expect(updated.imageMediaIds, listing.imageMediaIds);
      expect(updated.status, listing.status);
      expect(updated.moderationStatus, listing.moderationStatus);
      expect(updated.sellerUserId, listing.sellerUserId);
      expect(
        () => updated.imageMediaIds.add('media-3'),
        throwsUnsupportedError,
      );
    });

    test('is publicly visible only when active and approved', () {
      expect(fullListing().isPubliclyVisible, isTrue);
      expect(
        fullListing(status: ListingStatus.paused).isPubliclyVisible,
        isFalse,
      );
      expect(
        fullListing(
          moderation: ListingModerationStatus.pendingReview,
        ).isPubliclyVisible,
        isFalse,
      );
      expect(
        fullListing(
          moderation: ListingModerationStatus.rejected,
        ).isPubliclyVisible,
        isFalse,
      );
    });

    test('rejects blank title, category and price labels', () {
      expect(
        () => StoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller-sentinel',
          kind: ListingKind.product,
          title: ' ',
          categoryLabel: 'Electronics',
          priceLabel: r'$650',
          status: ListingStatus.draft,
          moderationStatus: ListingModerationStatus.pendingReview,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => StoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller-sentinel',
          kind: ListingKind.product,
          title: 'iPad',
          categoryLabel: '',
          priceLabel: r'$650',
          status: ListingStatus.draft,
          moderationStatus: ListingModerationStatus.pendingReview,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
      expect(
        () => StoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller-sentinel',
          kind: ListingKind.product,
          title: 'iPad',
          categoryLabel: 'Electronics',
          priceLabel: '',
          status: ListingStatus.draft,
          moderationStatus: ListingModerationStatus.pendingReview,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('legacy free-text records keep a label but no category id', () {
      final legacy = StoreListing(
        id: 'listing-legacy',
        sellerProfileId: 'seller-1',
        sellerUserId: 'auth-seller-sentinel',
        kind: ListingKind.product,
        title: 'iPad',
        categoryLabel: 'Electronics',
        priceLabel: r'$650',
        status: ListingStatus.active,
        moderationStatus: ListingModerationStatus.approved,
        stamp: stamp,
      );

      expect(legacy.categoryId, isNull);
      expect(legacy.categoryLabel, 'Electronics');
      expect(legacy.toPublicProjection().categoryId, isNull);
      expect(legacy.toPublicProjection().categoryLabel, 'Electronics');
    });

    test('a blank category id is rejected when one is provided', () {
      expect(
        () => StoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller-sentinel',
          kind: ListingKind.product,
          title: 'iPad',
          categoryLabel: 'Electronics',
          categoryId: ' ',
          priceLabel: r'$650',
          status: ListingStatus.draft,
          moderationStatus: ListingModerationStatus.pendingReview,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank media ids', () {
      expect(
        () => StoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller-sentinel',
          kind: ListingKind.product,
          title: 'iPad',
          categoryLabel: 'Electronics',
          priceLabel: r'$650',
          imageMediaIds: const ['media-1', ' '],
          status: ListingStatus.draft,
          moderationStatus: ListingModerationStatus.pendingReview,
          stamp: stamp,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PublicStoreListing projection', () {
    test('preserves public fields and excludes owner-only values', () {
      final projection = fullListing().toPublicProjection();

      expect(projection.id, 'listing-1');
      expect(projection.sellerProfileId, 'seller-1');
      expect(projection.kind, ListingKind.product);
      expect(projection.title, 'iPad Air 5th Gen 64GB');
      expect(projection.description, contains('charger'));
      expect(projection.categoryLabel, 'Electronics');
      expect(projection.categoryId, 'category-tablets');
      expect(projection.priceLabel, r'$650');
      expect(projection.serviceArea, 'Yonkers, NY');
      expect(projection.availability, 'Available today');
      expect(projection.imageMediaIds, ['media-1', 'media-2']);
      expect(projection.publishedAt, isNotNull);

      final rendered = projection.toString();
      expect(rendered.contains('auth-seller-sentinel'), isFalse);
      expect(rendered.contains('active'), isFalse);
      expect(rendered.contains('approved'), isFalse);
    });

    test('labels are display data; ids identify the category', () {
      final first = fullListing().toPublicProjection();
      final second = StoreListing(
        id: 'listing-2',
        sellerProfileId: 'seller-2',
        sellerUserId: 'auth-seller-2',
        kind: ListingKind.product,
        title: 'Galaxy Tab',
        categoryLabel: 'Electronics',
        categoryId: 'category-android-tablets',
        priceLabel: r'$420',
        status: ListingStatus.active,
        moderationStatus: ListingModerationStatus.approved,
        stamp: stamp,
      ).toPublicProjection();

      expect(first.categoryLabel, second.categoryLabel);
      expect(first.categoryId, isNot(second.categoryId));
    });

    test('rejects blank public display values and blank media ids', () {
      expect(
        () => PublicStoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          kind: ListingKind.service,
          title: '',
          categoryLabel: 'Home services',
          priceLabel: r'From $120',
        ),
        throwsArgumentError,
      );
      expect(
        () => PublicStoreListing(
          id: 'listing-1',
          sellerProfileId: ' ',
          kind: ListingKind.service,
          title: 'Pressure washing',
          categoryLabel: 'Home services',
          priceLabel: r'From $120',
        ),
        throwsArgumentError,
      );
      expect(
        () => PublicStoreListing(
          id: 'listing-1',
          sellerProfileId: 'seller-1',
          kind: ListingKind.service,
          title: 'Pressure washing',
          categoryLabel: 'Home services',
          priceLabel: r'From $120',
          imageMediaIds: const [''],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Store listing commands', () {
    test('create carries the catalogue category id and publish intent', () {
      final command = CreateStoreListingCommand(
        kind: ListingKind.service,
        title: 'Pressure washing',
        description: 'Driveways, patios, and exterior surfaces.',
        categoryId: 'category-home-services',
        priceLabel: r'From $120',
        serviceArea: 'Within 15 miles',
        availability: 'Next opening: Friday',
        imageMediaIds: const ['media-9'],
        publishIntent: ListingPublishIntent.publish,
        idempotencyKey: 'listing-create-1',
      );

      expect(command.kind, ListingKind.service);
      expect(command.categoryId, 'category-home-services');
      expect(command.publishIntent, ListingPublishIntent.publish);
      expect(command.imageMediaIds, ['media-9']);
      expect(command.idempotencyKey, 'listing-create-1');
    });

    test('update replaces all editable values at an expected revision', () {
      final command = UpdateStoreListingCommand(
        listingId: 'listing-1',
        expectedRevision: 3,
        title: 'Pressure washing',
        description: 'Updated details.',
        categoryId: 'category-home-services',
        priceLabel: r'$140',
        serviceArea: 'Within 20 miles',
        availability: 'Weekdays',
        imageMediaIds: const [],
        idempotencyKey: 'listing-update-1',
      );

      expect(command.expectedRevision, 3);
      expect(command.categoryId, 'category-home-services');
      expect(command.description, 'Updated details.');
      expect(command.imageMediaIds, isEmpty);
    });

    test('create and update require a real catalogue category id', () {
      expect(
        () => CreateStoreListingCommand(
          kind: ListingKind.product,
          title: 'iPad',
          categoryId: '  ',
          priceLabel: r'$650',
          idempotencyKey: 'listing-create-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateStoreListingCommand(
          listingId: 'listing-1',
          expectedRevision: 3,
          title: 'iPad',
          categoryId: '',
          priceLabel: r'$650',
          idempotencyKey: 'listing-update-1',
        ),
        throwsArgumentError,
      );
    });

    test('reject blank media ids in create and update', () {
      expect(
        () => CreateStoreListingCommand(
          kind: ListingKind.product,
          title: 'iPad',
          categoryId: 'category-tablets',
          priceLabel: r'$650',
          imageMediaIds: const ['media-1', ' '],
          idempotencyKey: 'listing-create-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateStoreListingCommand(
          listingId: 'listing-1',
          expectedRevision: 3,
          title: 'iPad',
          categoryId: 'category-tablets',
          priceLabel: r'$650',
          imageMediaIds: const [''],
          idempotencyKey: 'listing-update-1',
        ),
        throwsArgumentError,
      );
    });

    test('publication, archive and duplicate keep server ownership', () {
      final publish = SetStoreListingPublicationCommand(
        listingId: 'listing-1',
        expectedRevision: 3,
        publish: false,
        idempotencyKey: 'listing-publish-1',
      );
      expect(publish.publish, isFalse);

      final archive = ArchiveStoreListingCommand(
        listingId: 'listing-1',
        expectedRevision: 3,
        reason: 'No longer offered',
        idempotencyKey: 'listing-archive-1',
      );
      expect(archive.reason, 'No longer offered');

      final duplicate = DuplicateStoreListingCommand(
        listingId: 'listing-1',
        idempotencyKey: 'listing-duplicate-1',
      );
      expect(duplicate.listingId, 'listing-1');
    });

    test('reject blank keys and revisions below one', () {
      expect(
        () => CreateStoreListingCommand(
          kind: ListingKind.product,
          title: 'iPad',
          categoryId: 'category-tablets',
          priceLabel: r'$650',
          idempotencyKey: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateStoreListingCommand(
          listingId: 'listing-1',
          expectedRevision: 0,
          title: 'iPad',
          categoryId: 'category-tablets',
          priceLabel: r'$650',
          idempotencyKey: 'listing-update-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => ArchiveStoreListingCommand(
          listingId: 'listing-1',
          expectedRevision: 3,
          idempotencyKey: ' ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('StoreListingSummary', () {
    test('totals the server-derived status counts', () {
      final summary = StoreListingSummary(
        draftCount: 2,
        activeCount: 3,
        pausedCount: 1,
        archivedCount: 4,
      );

      expect(summary.activeCount, 3);
      expect(summary.totalCount, 10);
    });

    test('rejects negative counts', () {
      expect(() => StoreListingSummary(activeCount: -1), throwsArgumentError);
    });
  });
}
