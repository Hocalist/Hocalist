/// Buyer request contracts for Phase 2.
///
/// A request is a buyer-owned record linked by IDs to its buyer profile and
/// identity. Request status, revision and timestamps are server-owned; the
/// draft below is the complete editable input set captured by the create and
/// edit screens.
///
/// Acceptance concurrency, expiry policy and reopened-request eligibility are
/// unresolved business decisions. The contract carries relationships and
/// revisions so those policies can be decided later without reshaping data.
library;

import 'category_answers.dart';

import 'common.dart';
import 'failures.dart';
import 'money.dart';

enum RequestKind { product, service }

/// Product condition values shown as `New` / `Used`.
enum ProductCondition { newItem, used }

/// Service type values shown as `Single` / `Ongoing`.
enum ServiceType { oneTime, ongoing }

/// Server-owned request lifecycle. Reopening a request returns it to [active]
/// with a new revision; it is not a separate stored state.
enum RequestStatus { draft, active, closed, expired, cancelled }

/// Where the buyer needs the product or service.
class RequestCoordinates {
  RequestCoordinates({required this.latitude, required this.longitude}) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw ArgumentError('Invalid request coordinates');
    }
  }
  final double latitude;
  final double longitude;
  @override
  bool operator ==(Object other) =>
      other is RequestCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;
  @override
  int get hashCode => Object.hash(latitude, longitude);
  @override
  String toString() => 'RequestCoordinates(redacted)';
}

class RequestLocation {
  const RequestLocation.homeAddress({this.timezoneId})
    : useHomeAddress = true,
      address = null,
      coordinates = null;

  factory RequestLocation.custom({
    required PostalAddress address,
    RequestCoordinates? coordinates,
    String? timezoneId,
  }) {
    if (address.isEmpty) {
      throw ArgumentError.value(
        address,
        'address',
        'a custom request location needs at least one address field',
      );
    }
    return RequestLocation._(
      address: address,
      coordinates: coordinates,
      timezoneId: timezoneId,
    );
  }

  const RequestLocation._({
    required this.address,
    this.coordinates,
    this.timezoneId,
  }) : useHomeAddress = false;

  final bool useHomeAddress;
  final String? timezoneId;

  /// Custom address when [useHomeAddress] is false. Private until the buyer
  /// chooses to share it with a selected seller.
  final PostalAddress? address;

  /// Exact buyer-confirmed position; never part of seller lead discovery.
  final RequestCoordinates? coordinates;

  @override
  bool operator ==(Object other) =>
      other is RequestLocation &&
      other.useHomeAddress == useHomeAddress &&
      other.address == address &&
      other.coordinates == coordinates &&
      other.timezoneId == timezoneId;

  @override
  int get hashCode =>
      Object.hash(useHomeAddress, address, coordinates, timezoneId);

  @override
  String toString() => useHomeAddress
      ? 'RequestLocation.homeAddress()'
      : 'RequestLocation.custom($address)';
}

/// Complete editable request input captured by the request forms.
///
/// Incomplete drafts are legitimate while a form is being filled in, so this
/// type allows a blank title and reports it through [validationIssues].
class RequestDraft {
  factory RequestDraft({
    required RequestKind kind,
    String title = '',
    String description = '',
    List<String> imageMediaIds = const [],
    ProductCondition? condition,
    ServiceType? serviceType,
    int quantity = 1,
    MoneyRange? budget,
    bool acceptsHigherOffers = false,
    String? categoryId,
    List<CategoryAnswer> categoryAnswers = const [],
    RequestLocation location = const RequestLocation.homeAddress(),
  }) {
    if (quantity < 1 || quantity > 99) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'must be between 1 and 99',
      );
    }
    if (categoryId != null && categoryId.trim().isEmpty) {
      throw ArgumentError.value(
        categoryId,
        'categoryId',
        'must not be blank when provided',
      );
    }
    return RequestDraft._(
      kind: kind,
      title: title,
      description: description,
      imageMediaIds: List.unmodifiable(imageMediaIds),
      condition: condition,
      serviceType: serviceType,
      quantity: quantity,
      budget: budget ?? MoneyRange.empty,
      acceptsHigherOffers: acceptsHigherOffers,
      categoryId: categoryId,
      categoryAnswers: List.unmodifiable(categoryAnswers),
      location: location,
    );
  }

  const RequestDraft._({
    required this.kind,
    required this.title,
    required this.description,
    required this.imageMediaIds,
    required this.condition,
    required this.serviceType,
    required this.quantity,
    required this.budget,
    required this.acceptsHigherOffers,
    required this.categoryId,
    required this.categoryAnswers,
    required this.location,
  });

  final RequestKind kind;
  final String title;
  final String description;
  final List<String> imageMediaIds;

  /// Product-only value. Must be null for service requests.
  final ProductCondition? condition;

  /// Service-only value. Must be null for product requests.
  final ServiceType? serviceType;

  /// Product quantity. Always 1 for service requests.
  final int quantity;

  /// Optional budget range.
  final MoneyRange budget;

  final bool acceptsHigherOffers;

  /// Backend-managed category identifier; free text until the catalogue
  /// integration replaces it.
  final String? categoryId;

  final List<CategoryAnswer> categoryAnswers;

  final RequestLocation location;

  /// Immutable update with explicit keep/set/clear semantics.
  ///
  /// - omit a field to keep its current value
  /// - pass a value to set it
  /// - pass `clearCondition` / `clearServiceType` / `clearCategory` to null it
  ///
  /// Clearing is explicit so a kind transition can remove the value that no
  /// longer applies without the model silently deciding lifecycle rules.
  RequestDraft copyWith({
    RequestKind? kind,
    String? title,
    String? description,
    List<String>? imageMediaIds,
    ProductCondition? condition,
    bool clearCondition = false,
    ServiceType? serviceType,
    bool clearServiceType = false,
    int? quantity,
    MoneyRange? budget,
    bool? acceptsHigherOffers,
    String? categoryId,
    bool clearCategory = false,
    List<CategoryAnswer>? categoryAnswers,
    RequestLocation? location,
  }) {
    if (clearCondition && condition != null) {
      throw ArgumentError(
        'condition and clearCondition are mutually exclusive',
      );
    }
    if (clearServiceType && serviceType != null) {
      throw ArgumentError(
        'serviceType and clearServiceType are mutually exclusive',
      );
    }
    if (clearCategory && categoryId != null) {
      throw ArgumentError(
        'categoryId and clearCategory are mutually exclusive',
      );
    }
    return RequestDraft(
      kind: kind ?? this.kind,
      title: title ?? this.title,
      description: description ?? this.description,
      imageMediaIds: imageMediaIds ?? this.imageMediaIds,
      condition: clearCondition ? null : (condition ?? this.condition),
      serviceType: clearServiceType ? null : (serviceType ?? this.serviceType),
      quantity: quantity ?? this.quantity,
      budget: budget ?? this.budget,
      acceptsHigherOffers: acceptsHigherOffers ?? this.acceptsHigherOffers,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryAnswers: clearCategory
          ? const []
          : (categoryAnswers ?? this.categoryAnswers),
      location: location ?? this.location,
    );
  }

  /// Advisory checks for the form. The server re-validates every field.
  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'title',
          code: ValidationCodes.requiredField,
          message: 'Add a clear request title.',
        ),
      );
    } else if (trimmedTitle.length > 160) {
      issues.add(
        const ValidationIssue(
          field: 'title',
          code: ValidationCodes.tooLong,
          message: 'Keep the request title within 160 characters.',
        ),
      );
    }
    if (description.length > 500) {
      issues.add(
        const ValidationIssue(
          field: 'description',
          code: ValidationCodes.tooLong,
          message: 'Keep the description within 500 characters.',
        ),
      );
    }
    switch (kind) {
      case RequestKind.product:
        if (condition == null) {
          issues.add(
            const ValidationIssue(
              field: 'condition',
              code: ValidationCodes.requiredField,
              message: 'Choose whether the product is new or used.',
            ),
          );
        }
        if (serviceType != null) {
          issues.add(
            const ValidationIssue(
              field: 'serviceType',
              code: ValidationCodes.invalidValue,
              message: 'Service type does not apply to product requests.',
            ),
          );
        }
      case RequestKind.service:
        if (serviceType == null) {
          issues.add(
            const ValidationIssue(
              field: 'serviceType',
              code: ValidationCodes.requiredField,
              message: 'Choose whether the service is single or ongoing.',
            ),
          );
        }
        if (condition != null) {
          issues.add(
            const ValidationIssue(
              field: 'condition',
              code: ValidationCodes.invalidValue,
              message: 'Condition does not apply to service requests.',
            ),
          );
        }
        if (quantity != 1) {
          issues.add(
            const ValidationIssue(
              field: 'quantity',
              code: ValidationCodes.invalidValue,
              message: 'Service requests keep a quantity of 1.',
            ),
          );
        }
    }
    return List<ValidationIssue>.unmodifiable(issues);
  }

  /// Redacted on purpose: request text is buyer content and must not reach
  /// logs. Shape fields stay visible for debugging.
  @override
  String toString() =>
      'RequestDraft(${kind.name}, title: [redacted], quantity: $quantity, '
      'budget: $budget)';
}

/// A persisted buyer request with server-owned state.
class MarketplaceRequest {
  MarketplaceRequest({
    required String id,
    required String buyerProfileId,
    required String buyerUserId,
    required this.draft,
    required this.status,
    required this.stamp,
    DateTime? firstAcceptedAt,
    DateTime? acceptanceExpiresAt,
    String? purchaseOfferId,
    DateTime? purchaseSelectedAt,
    this.discoveryOpen,
  }) : id = requireNonBlank(id, 'id'),
       buyerProfileId = requireNonBlank(buyerProfileId, 'buyerProfileId'),
       buyerUserId = requireNonBlank(buyerUserId, 'buyerUserId'),
       firstAcceptedAt = firstAcceptedAt?.toUtc(),
       acceptanceExpiresAt = acceptanceExpiresAt?.toUtc(),
       purchaseOfferId = optionalNonBlank(purchaseOfferId, 'purchaseOfferId'),
       purchaseSelectedAt = purchaseSelectedAt?.toUtc();

  final String id;
  final String buyerProfileId;
  final String buyerUserId;

  /// Editable field values as last accepted by the server.
  final RequestDraft draft;

  /// Server-owned lifecycle status. Never set by a client command.
  final RequestStatus status;

  /// Server-owned start of the seven-day acceptance countdown. Set once at the
  /// first acceptance; later acceptances never reset it.
  final DateTime? firstAcceptedAt;

  /// Exclusive end of the request acceptance window. Discovery and new offers
  /// close here. Accepted meetings keep their own next-local-midnight cutoff.
  final DateTime? acceptanceExpiresAt;

  /// The accepted seller designated for the final purchase, when chosen.
  final String? purchaseOfferId;

  final DateTime? purchaseSelectedAt;

  /// Server-computed discovery state; null when the backend has not supplied
  /// it (pre-upgrade server) so the UI can fall back to [status].
  final bool? discoveryOpen;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  MarketplaceRequest copyWith({
    RequestDraft? draft,
    RequestStatus? status,
    RecordStamp? stamp,
    DateTime? firstAcceptedAt,
    DateTime? acceptanceExpiresAt,
    String? purchaseOfferId,
    DateTime? purchaseSelectedAt,
    bool? discoveryOpen,
  }) {
    return MarketplaceRequest(
      id: id,
      buyerProfileId: buyerProfileId,
      buyerUserId: buyerUserId,
      draft: draft ?? this.draft,
      status: status ?? this.status,
      stamp: stamp ?? this.stamp,
      firstAcceptedAt: firstAcceptedAt ?? this.firstAcceptedAt,
      acceptanceExpiresAt: acceptanceExpiresAt ?? this.acceptanceExpiresAt,
      purchaseOfferId: purchaseOfferId ?? this.purchaseOfferId,
      purchaseSelectedAt: purchaseSelectedAt ?? this.purchaseSelectedAt,
      discoveryOpen: discoveryOpen ?? this.discoveryOpen,
    );
  }

  @override
  String toString() =>
      'MarketplaceRequest($id, ${status.name}, revision: ${stamp.revision})';
}

/// Creates a request from complete editable values.
class CreateRequestCommand {
  CreateRequestCommand({required this.draft, required String idempotencyKey})
    : idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey');

  final RequestDraft draft;

  /// Client-generated key so a retried submit does not duplicate a request.
  final String idempotencyKey;
}

/// Replaces all editable request values at an expected revision.
class UpdateRequestCommand {
  UpdateRequestCommand({
    required String requestId,
    required this.expectedRevision,
    required this.draft,
    required String idempotencyKey,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String requestId;
  final int expectedRevision;
  final RequestDraft draft;
  final String idempotencyKey;
}

/// Closes or withdraws a request, stopping new offers.
class CloseRequestCommand {
  CloseRequestCommand({
    required String requestId,
    required this.expectedRevision,
    required String idempotencyKey,
    this.reason,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String requestId;
  final int expectedRevision;
  final String idempotencyKey;
  final String? reason;
}

/// Reopens a closed or failed request so sellers can respond again.
///
/// Backup-seller eligibility, reservations and reward effects are unresolved
/// policy; the command only carries the revision it expects.
class ReopenRequestCommand {
  ReopenRequestCommand({
    required String requestId,
    required this.expectedRevision,
    required String idempotencyKey,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final String requestId;
  final int expectedRevision;
  final String idempotencyKey;
}

/// Server-side ordering for the seller Leads list.
enum SellerLeadSort { bestMatch, closest, highestMatch, mostPurchases }

/// Filters selected on the seller Leads screen.
///
/// Filter values are inputs; which requests a seller may see and how budget
/// matching, distance or match ranking is calculated stays server policy.
class SellerLeadQuery {
  SellerLeadQuery({
    this.kind,
    String? categoryId,
    String? areaLabel,
    this.budgetFilter,
    this.sort = SellerLeadSort.bestMatch,
    this.page = PageQuery.standard,
  }) : categoryId = optionalNonBlank(categoryId, 'categoryId'),
       areaLabel = optionalNonBlank(areaLabel, 'areaLabel');

  final RequestKind? kind;
  final String? categoryId;
  final String? areaLabel;

  /// Optional budget overlap filter built from the selected band.
  final MoneyRange? budgetFilter;

  final SellerLeadSort sort;
  final PageQuery page;
}

/// Seller-visible projection of one buyer request.
///
/// This is a separate read model from [MarketplaceRequest]: it contains no
/// buyer address, no contact details and no other sellers' offers. The
/// optional reputation fields may be withheld by the server under its
/// visibility policy; the client must render absent values as unavailable.
class SellerLeadProjection {
  SellerLeadProjection({
    required String requestId,
    required this.kind,
    required String title,
    this.description = '',
    this.categoryAnswers = const [],
    this.condition,
    this.serviceType,
    this.quantity = 1,
    this.budget = MoneyRange.empty,
    this.acceptsHigherOffers = false,
    String? categoryId,
    required String buyerProfileId,
    required String buyerDisplayName,
    String? areaLabel,
    this.distanceMiles,
    this.matchPercent,
    this.verifiedPurchaseCount,
    this.lastCompletedItemLabel,
    this.preferredMeetupLabel,
    this.locationTimezone,
    this.imageMediaIds = const [],
    DateTime? publishedAt,
    required this.requestRevision,
    DateTime? acceptanceExpiresAt,
    this.discoveryOpen,
  }) : requestId = requireNonBlank(requestId, 'requestId'),
       title = requireNonBlank(title, 'title'),
       buyerProfileId = requireNonBlank(buyerProfileId, 'buyerProfileId'),
       buyerDisplayName = requireNonBlank(buyerDisplayName, 'buyerDisplayName'),
       categoryId = optionalNonBlank(categoryId, 'categoryId'),
       areaLabel = optionalNonBlank(areaLabel, 'areaLabel'),
       publishedAt = publishedAt?.toUtc(),
       acceptanceExpiresAt = acceptanceExpiresAt?.toUtc() {
    if (quantity < 1 || quantity > 99) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'must be between 1 and 99',
      );
    }
    if (distanceMiles != null &&
        (!distanceMiles!.isFinite || distanceMiles! < 0)) {
      throw ArgumentError.value(
        distanceMiles,
        'distanceMiles',
        'must be a finite, non-negative number',
      );
    }
    if (matchPercent != null && (matchPercent! < 0 || matchPercent! > 100)) {
      throw ArgumentError.value(
        matchPercent,
        'matchPercent',
        'must be between 0 and 100',
      );
    }
    if (verifiedPurchaseCount != null && verifiedPurchaseCount! < 0) {
      throw ArgumentError.value(
        verifiedPurchaseCount,
        'verifiedPurchaseCount',
        'must not be negative',
      );
    }
    if (requestRevision < 1) {
      throw ArgumentError.value(
        requestRevision,
        'requestRevision',
        'must be at least 1',
      );
    }
  }

  final String requestId;
  final String? locationTimezone;
  final List<String> imageMediaIds;
  final RequestKind kind;
  final String title;
  final String description;
  final List<CategoryAnswer> categoryAnswers;
  final ProductCondition? condition;
  final ServiceType? serviceType;
  final int quantity;
  final MoneyRange budget;
  final bool acceptsHigherOffers;
  final String? categoryId;

  /// Public buyer identity for the lead card.
  final String buyerProfileId;
  final String buyerDisplayName;

  /// Approximate area only; the exact address is never part of this model.
  final String? areaLabel;

  /// Server-computed distance hint, when the seller location is known.
  final double? distanceMiles;

  /// Server-computed match score, when ranking inputs are available.
  final int? matchPercent;

  /// Server-verified purchase count shown as reputation context.
  final int? verifiedPurchaseCount;

  /// Last completed item label, when the server chooses to expose it.
  final String? lastCompletedItemLabel;

  /// Preferred meetup summary, when the server chooses to expose it.
  final String? preferredMeetupLabel;

  final DateTime? publishedAt;

  /// Exclusive end of the request acceptance window for an already-accepted
  /// negotiation, when the server exposes it to the seller.
  final DateTime? acceptanceExpiresAt;

  /// Server-computed discovery state; null when the backend has not supplied
  /// it (pre-upgrade server).
  final bool? discoveryOpen;

  /// Request revision this projection was built from.
  final int requestRevision;

  @override
  String toString() =>
      'SellerLeadProjection($requestId, ${kind.name}, '
      'revision: $requestRevision, area: $areaLabel)';
}
