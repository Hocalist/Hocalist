/// Strict decoders for the marketplace wire shapes from draft 020.
///
/// Every decoder validates required fields, types, enum values, positive
/// revisions and parseable timestamps. Failures raise
/// [MarketplaceDecodeException] with a safe field path; request text, addresses
/// and server messages are never included.
library;

import '../../../domain/phase2/catalogue.dart';
import '../../../domain/phase2/category_answers.dart';
import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/discovery.dart';
import '../../../domain/phase2/money.dart';
import '../../../domain/phase2/offers.dart';
import '../../../domain/phase2/requests.dart';
import '../../../domain/phase2/schedule.dart';
import '../../../domain/phase2/store_listings.dart';
import '../accounts/account_codecs.dart' show AccountDecodeException;
import '../accounts/timestamptz.dart';

List<CategoryAnswer> _categoryAnswers(Map<String, Object?> row) {
  try {
    return CategoryAnswer.decode(row['category_answers']);
  } on FormatException {
    throw const MarketplaceDecodeException('category_answers');
  }
}

class MarketplaceDecodeException implements Exception {
  const MarketplaceDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'MarketplaceDecodeException($detail)';
}

/// Private confirmed pins are an optional pair, never a partial destination.
double? decodePlaceCoordinate(Map<String, Object?> row, String field) {
  final latitude = row['place_latitude'];
  final longitude = row['place_longitude'];
  if (latitude == null && longitude == null) return null;
  if (latitude is! num ||
      longitude is! num ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    throw const MarketplaceDecodeException('place_coordinates');
  }
  return (field == 'place_latitude' ? latitude : longitude).toDouble();
}

Map<String, Object?> decodeObject(Object? data, String context) {
  if (data is! Map) throw MarketplaceDecodeException('$context.result');
  try {
    return Map<String, Object?>.from(data);
  } on TypeError {
    throw MarketplaceDecodeException('$context.result');
  }
}

List<Map<String, Object?>> decodeObjectList(Object? data, String context) {
  if (data is! List) throw MarketplaceDecodeException('$context.items');
  final rows = <Map<String, Object?>>[];
  for (final entry in data) {
    if (entry is! Map) throw MarketplaceDecodeException('$context.item');
    try {
      rows.add(Map<String, Object?>.from(entry));
    } on TypeError {
      throw MarketplaceDecodeException('$context.item');
    }
  }
  return rows;
}

/// One page envelope with `items` and `next_cursor`.
PageSlice<T> decodePage<T>(
  Map<String, Object?> json,
  String context,
  T Function(Map<String, Object?> row, String context) decode,
) {
  final rows = decodeObjectList(json['items'], context);
  final items = <T>[];
  for (var index = 0; index < rows.length; index++) {
    items.add(decode(rows[index], '$context.items[$index]'));
  }
  final cursor = json['next_cursor'];
  if (cursor != null && cursor is! String) {
    throw MarketplaceDecodeException('$context.next_cursor');
  }
  return PageSlice<T>(
    items: items,
    nextCursor: cursor == null || (cursor as String).trim().isEmpty
        ? null
        : cursor,
  );
}

// ---------------------------------------------------------------------------
// Wire enum mappings
// ---------------------------------------------------------------------------

RequestKind requestKindFromWire(String wire, String context) => switch (wire) {
  'product' => RequestKind.product,
  'service' => RequestKind.service,
  _ => throw MarketplaceDecodeException(context),
};

String requestKindToWire(RequestKind kind) => kind.name;

ProductCondition productConditionFromWire(String wire, String context) =>
    switch (wire) {
      'new_item' => ProductCondition.newItem,
      'used' => ProductCondition.used,
      _ => throw MarketplaceDecodeException(context),
    };

String productConditionToWire(ProductCondition value) =>
    value == ProductCondition.newItem ? 'new_item' : 'used';

ServiceType serviceTypeFromWire(String wire, String context) => switch (wire) {
  'one_time' => ServiceType.oneTime,
  'ongoing' => ServiceType.ongoing,
  _ => throw MarketplaceDecodeException(context),
};

String serviceTypeToWire(ServiceType value) =>
    value == ServiceType.oneTime ? 'one_time' : 'ongoing';

RequestStatus requestStatusFromWire(String wire, String context) =>
    switch (wire) {
      'draft' => RequestStatus.draft,
      'active' => RequestStatus.active,
      'closed' => RequestStatus.closed,
      'expired' => RequestStatus.expired,
      'cancelled' => RequestStatus.cancelled,
      _ => throw MarketplaceDecodeException(context),
    };

OfferStatus offerStatusFromWire(String wire, String context) => switch (wire) {
  'submitted' => OfferStatus.submitted,
  'selected' => OfferStatus.selected,
  'withdrawn' => OfferStatus.withdrawn,
  'declined' => OfferStatus.declined,
  'completed' => OfferStatus.completed,
  'cancelled' => OfferStatus.cancelled,
  'expired' => OfferStatus.expired,
  _ => throw MarketplaceDecodeException(context),
};

OfferRevisionStatus offerRevisionStatusFromWire(String wire, String context) =>
    switch (wire) {
      'proposed' => OfferRevisionStatus.proposed,
      'accepted' => OfferRevisionStatus.accepted,
      'superseded' => OfferRevisionStatus.superseded,
      'rejected' => OfferRevisionStatus.rejected,
      'withdrawn' => OfferRevisionStatus.withdrawn,
      _ => throw MarketplaceDecodeException(context),
    };

MeetupPlaceChoice placeChoiceFromWire(String wire, String context) =>
    switch (wire) {
      'seller_business' => MeetupPlaceChoice.sellerBusiness,
      'buyer_location' => MeetupPlaceChoice.buyerLocation,
      'specific_place' => MeetupPlaceChoice.specificPlace,
      _ => throw MarketplaceDecodeException(context),
    };

String placeChoiceToWire(MeetupPlaceChoice value) => switch (value) {
  MeetupPlaceChoice.sellerBusiness => 'seller_business',
  MeetupPlaceChoice.buyerLocation => 'buyer_location',
  MeetupPlaceChoice.specificPlace => 'specific_place',
};

CatalogueScope catalogueScopeFromWire(String wire, String context) =>
    switch (wire) {
      'product' => CatalogueScope.product,
      'service' => CatalogueScope.service,
      'both' => CatalogueScope.both,
      _ => throw MarketplaceDecodeException(context),
    };

CatalogueEntryStatus catalogueStatusFromWire(String wire, String context) =>
    switch (wire) {
      'active' => CatalogueEntryStatus.active,
      'retired' => CatalogueEntryStatus.retired,
      _ => throw MarketplaceDecodeException(context),
    };

CatalogueSelectionMode selectionModeFromWire(String wire, String context) =>
    switch (wire) {
      'single' => CatalogueSelectionMode.single,
      'multiple' => CatalogueSelectionMode.multiple,
      _ => throw MarketplaceDecodeException(context),
    };

ListingKind listingKindFromWire(String wire, String context) => switch (wire) {
  'product' => ListingKind.product,
  'service' => ListingKind.service,
  _ => throw MarketplaceDecodeException(context),
};

ListingStatus listingStatusFromWire(String wire, String context) =>
    switch (wire) {
      'draft' => ListingStatus.draft,
      'active' => ListingStatus.active,
      'paused' => ListingStatus.paused,
      'archived' => ListingStatus.archived,
      _ => throw MarketplaceDecodeException(context),
    };

ListingModerationStatus moderationStatusFromWire(String wire, String context) =>
    switch (wire) {
      'pending_review' => ListingModerationStatus.pendingReview,
      'approved' => ListingModerationStatus.approved,
      'rejected' => ListingModerationStatus.rejected,
      _ => throw MarketplaceDecodeException(context),
    };

RepeatedTimeOccurrence repeatedTimeOccurrenceFromWire(
  String wire,
  String context,
) => switch (wire) {
  'earlier' => RepeatedTimeOccurrence.earlier,
  'later' => RepeatedTimeOccurrence.later,
  _ => throw MarketplaceDecodeException(context),
};

String repeatedTimeOccurrenceToWire(RepeatedTimeOccurrence occurrence) =>
    switch (occurrence) {
      RepeatedTimeOccurrence.earlier => 'earlier',
      RepeatedTimeOccurrence.later => 'later',
    };

// ---------------------------------------------------------------------------
// Field readers
// ---------------------------------------------------------------------------

String _requireString(
  Map<String, Object?> row,
  String field,
  String context, {
  bool allowEmpty = false,
}) {
  final value = row[field];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw MarketplaceDecodeException(context);
  }
  return value;
}

String? _optionalString(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! String) throw MarketplaceDecodeException(field);
  return value.isEmpty ? null : value;
}

int _requireInt(Map<String, Object?> row, String field, String context) {
  final value = row[field];
  if (value is! num) throw MarketplaceDecodeException(context);
  final intValue = value.toInt();
  if (intValue != value) throw MarketplaceDecodeException(context);
  return intValue;
}

int _requirePositiveInt(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = _requireInt(row, field, context);
  if (value < 1) throw MarketplaceDecodeException(context);
  return value;
}

int? _optionalInt(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! num) throw MarketplaceDecodeException(field);
  return value.toInt();
}

bool _requireBool(Map<String, Object?> row, String field, String context) {
  final value = row[field];
  if (value is! bool) throw MarketplaceDecodeException(context);
  return value;
}

/// Optional boolean for additive server fields; absent stays null so an older
/// server never forces a fabricated default.
bool? _optionalBool(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! bool) throw MarketplaceDecodeException(field);
  return value;
}

/// Optional finite double for additive server fields.
double? _optionalDouble(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw MarketplaceDecodeException(field);
  }
  return value.toDouble();
}

List<String> _optionalStringList(Map<String, Object?> row, String field) {
  final value = row[field];
  if (value == null) return const [];
  if (value is! List) throw MarketplaceDecodeException(field);
  final result = <String>[];
  for (final entry in value) {
    if (entry is! String) throw MarketplaceDecodeException(field);
    result.add(entry);
  }
  return List<String>.unmodifiable(result);
}

DateTime _requireTimestamp(
  Map<String, Object?> row,
  String field,
  String context,
) {
  final value = row[field];
  if (value is! String) throw MarketplaceDecodeException(context);
  try {
    return parsePostgresTimestamptz(value, context: context);
  } on AccountDecodeException {
    throw MarketplaceDecodeException(context);
  }
}

DateTime? _optionalTimestamp(
  Map<String, Object?> row,
  String field,
  String context,
) {
  if (row[field] == null) return null;
  return _requireTimestamp(row, field, context);
}

List<String> _stringList(Object? value, String context) {
  if (value is! List) throw MarketplaceDecodeException(context);
  final out = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) {
      throw MarketplaceDecodeException(context);
    }
    out.add(entry);
  }
  return List<String>.unmodifiable(out);
}

RecordStamp _stamp(Map<String, Object?> row, String context) {
  return RecordStamp(
    revision: _requirePositiveInt(row, 'revision', '$context.revision'),
    createdAt: _requireTimestamp(row, 'created_at', '$context.created_at'),
    updatedAt: _requireTimestamp(row, 'updated_at', '$context.updated_at'),
  );
}

MoneyRange _budget(Map<String, Object?> row, String context) {
  final budget = row['budget'];
  if (budget is! Map) throw MarketplaceDecodeException('$context.budget');
  final map = Map<String, Object?>.from(budget);
  final currency = map['currency'];
  final minimum = _optionalInt(map, 'minimum_minor');
  final maximum = _optionalInt(map, 'maximum_minor');
  if (minimum == null && maximum == null) return MoneyRange.empty;
  if (currency is! String || currency.trim().isEmpty) {
    throw MarketplaceDecodeException('$context.budget.currency');
  }
  return MoneyRange(
    minimum: minimum == null
        ? null
        : Money(minorUnits: minimum, currencyCode: currency),
    maximum: maximum == null
        ? null
        : Money(minorUnits: maximum, currencyCode: currency),
  );
}

LocalDate _localDate(String value, String context) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) throw MarketplaceDecodeException(context);
  try {
    return LocalDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  }
}

LocalTime _localTime(String value, String context) {
  final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (match == null) throw MarketplaceDecodeException(context);
  try {
    return LocalTime(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
    );
  } on ArgumentError {
    throw MarketplaceDecodeException(context);
  }
}

// ---------------------------------------------------------------------------
// Catalogue and locations
// ---------------------------------------------------------------------------

CatalogueOption decodeCatalogueOptionJson(
  Map<String, Object?> row,
  String context,
) {
  return CatalogueOption(
    id: _requireString(row, 'id', '$context.id'),
    groupId: _requireString(row, 'group_id', '$context.group_id'),
    label: _requireString(row, 'label', '$context.label'),
    status: catalogueStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    sortOrder: _requireInt(row, 'sort_order', '$context.sort_order'),
    stamp: _stamp(row, context),
  );
}

CatalogueOptionGroup decodeCatalogueOptionGroupJson(
  Map<String, Object?> row,
  String context,
) {
  final options = <CatalogueOption>[];
  final rawOptions = row['options'];
  if (rawOptions != null) {
    final rows = decodeObjectList(rawOptions, context);
    for (var index = 0; index < rows.length; index++) {
      options.add(
        decodeCatalogueOptionJson(rows[index], '$context.options[$index]'),
      );
    }
  }
  return CatalogueOptionGroup(
    id: _requireString(row, 'id', '$context.id'),
    categoryId: _requireString(row, 'category_id', '$context.category_id'),
    label: _requireString(row, 'label', '$context.label'),
    selectionMode: selectionModeFromWire(
      _requireString(row, 'selection_mode', '$context.selection_mode'),
      '$context.selection_mode',
    ),
    isRequired: _requireBool(row, 'is_required', '$context.is_required'),
    status: catalogueStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    sortOrder: _requireInt(row, 'sort_order', '$context.sort_order'),
    stamp: _stamp(row, context),
  );
}

CatalogueCategory decodeCatalogueCategoryJson(
  Map<String, Object?> row,
  String context,
) {
  return CatalogueCategory(
    id: _requireString(row, 'id', '$context.id'),
    parentId: _optionalString(row, 'parent_id'),
    label: _requireString(row, 'label', '$context.label'),
    slug: _optionalString(row, 'slug'),
    scope: catalogueScopeFromWire(
      _requireString(row, 'scope', '$context.scope'),
      '$context.scope',
    ),
    status: catalogueStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    sortOrder: _requireInt(row, 'sort_order', '$context.sort_order'),
    stamp: _stamp(row, context),
  );
}

/// Categories with their nested option groups. The nested groups are decoded
/// separately through [decodeCatalogueOptionGroupJson] by the adapter.
List<CatalogueCategory> decodeCatalogueJson(
  Map<String, Object?> json,
  String context,
) {
  final rows = decodeObjectList(json['categories'], context);
  final categories = <CatalogueCategory>[];
  for (var index = 0; index < rows.length; index++) {
    categories.add(
      decodeCatalogueCategoryJson(rows[index], '$context.categories[$index]'),
    );
  }
  return categories;
}

List<CatalogueOptionGroup> decodeNestedOptionGroupsJson(
  Map<String, Object?> categoryJson,
  String context,
) {
  final rows = decodeObjectList(categoryJson['groups'], context);
  final groups = <CatalogueOptionGroup>[];
  for (var index = 0; index < rows.length; index++) {
    groups.add(
      decodeCatalogueOptionGroupJson(rows[index], '$context.groups[$index]'),
    );
  }
  return groups;
}

LocationEntry decodeLocationJson(Map<String, Object?> row, String context) {
  return LocationEntry(
    id: _requireString(row, 'id', '$context.id'),
    countryCode: _requireString(row, 'country_code', '$context.country_code'),
    region: _optionalString(row, 'region'),
    city: _optionalString(row, 'city'),
    label: _requireString(row, 'label', '$context.label'),
    timezoneId: _optionalString(row, 'timezone_id'),
    status: catalogueStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    sortOrder: _requireInt(row, 'sort_order', '$context.sort_order'),
    stamp: RecordStamp(
      revision: _requirePositiveInt(row, 'revision', '$context.revision'),
      createdAt: _requireTimestamp(row, 'created_at', '$context.created_at'),
      updatedAt: _requireTimestamp(row, 'updated_at', '$context.updated_at'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

RequestDraft _requestDraft(Map<String, Object?> row, String context) {
  final kind = requestKindFromWire(
    _requireString(row, 'kind', '$context.kind'),
    '$context.kind',
  );
  final condition = _optionalString(row, 'condition');
  final serviceType = _optionalString(row, 'service_type');
  final location = row['location'];
  if (location is! Map) throw MarketplaceDecodeException('$context.location');
  final locationMap = Map<String, Object?>.from(location);
  final useHomeAddress = _requireBool(
    locationMap,
    'use_home_address',
    '$context.location.use_home_address',
  );
  final address = PostalAddress(
    line1: _optionalString(locationMap, 'address_line1'),
    line2: _optionalString(locationMap, 'address_line2'),
    city: _optionalString(locationMap, 'city'),
    state: _optionalString(locationMap, 'region'),
    postalCode: _optionalString(locationMap, 'postal_code'),
    country: _optionalString(locationMap, 'country_code'),
  );
  RequestCoordinates? coordinates;
  final latitude = locationMap['latitude'];
  final longitude = locationMap['longitude'];
  if (latitude != null || longitude != null) {
    if (useHomeAddress ||
        latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw MarketplaceDecodeException('$context.location.coordinates');
    }
    coordinates = RequestCoordinates(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
  return RequestDraft(
    kind: kind,
    imageMediaIds: _optionalStringList(row, 'image_media_ids'),
    title: _requireString(row, 'title', '$context.title'),
    description: _requireString(
      row,
      'description',
      '$context.description',
      allowEmpty: true,
    ),
    condition: condition == null
        ? null
        : productConditionFromWire(condition, '$context.condition'),
    serviceType: serviceType == null
        ? null
        : serviceTypeFromWire(serviceType, '$context.service_type'),
    quantity: _requireInt(row, 'quantity', '$context.quantity'),
    budget: _budget(row, context),
    acceptsHigherOffers: _requireBool(
      row,
      'accepts_higher_offers',
      '$context.accepts_higher_offers',
    ),
    categoryId: _optionalString(row, 'category_id'),
    categoryAnswers: _categoryAnswers(row),
    location: useHomeAddress
        ? RequestLocation.homeAddress(
            timezoneId: _optionalString(locationMap, 'timezone_id'),
          )
        : RequestLocation.custom(
            address: address,
            coordinates: coordinates,
            timezoneId: _optionalString(locationMap, 'timezone_id'),
          ),
  );
}

MarketplaceRequest decodeRequestJson(Map<String, Object?> row, String context) {
  return MarketplaceRequest(
    id: _requireString(row, 'id', '$context.id'),
    buyerProfileId: _requireString(
      row,
      'buyer_profile_id',
      '$context.buyer_profile_id',
    ),
    buyerUserId: _requireString(row, 'buyer_user_id', '$context.buyer_user_id'),
    draft: _requestDraft(row, context),
    status: requestStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    stamp: _stamp(row, context),
    firstAcceptedAt: _optionalTimestamp(
      row,
      'first_accepted_at',
      '$context.first_accepted_at',
    ),
    acceptanceExpiresAt: _optionalTimestamp(
      row,
      'acceptance_expires_at',
      '$context.acceptance_expires_at',
    ),
    purchaseOfferId: _optionalString(row, 'purchase_offer_id'),
    purchaseSelectedAt: _optionalTimestamp(
      row,
      'purchase_selected_at',
      '$context.purchase_selected_at',
    ),
    discoveryOpen: _optionalBool(row, 'discovery_open'),
  );
}

SellerLeadProjection decodeLeadJson(Map<String, Object?> row, String context) {
  final condition = _optionalString(row, 'condition');
  final serviceType = _optionalString(row, 'service_type');
  return SellerLeadProjection(
    requestId: _requireString(row, 'request_id', '$context.request_id'),
    kind: requestKindFromWire(
      _requireString(row, 'kind', '$context.kind'),
      '$context.kind',
    ),
    title: _requireString(row, 'title', '$context.title'),
    description: _requireString(
      row,
      'description',
      '$context.description',
      allowEmpty: true,
    ),
    condition: condition == null
        ? null
        : productConditionFromWire(condition, '$context.condition'),
    serviceType: serviceType == null
        ? null
        : serviceTypeFromWire(serviceType, '$context.service_type'),
    quantity: _requireInt(row, 'quantity', '$context.quantity'),
    budget: _budget(row, context),
    acceptsHigherOffers: _requireBool(
      row,
      'accepts_higher_offers',
      '$context.accepts_higher_offers',
    ),
    categoryId: _optionalString(row, 'category_id'),
    categoryAnswers: _categoryAnswers(row),
    buyerProfileId: _requireString(
      row,
      'buyer_profile_id',
      '$context.buyer_profile_id',
    ),
    buyerDisplayName: _requireString(
      row,
      'buyer_display_name',
      '$context.buyer_display_name',
    ),
    areaLabel: _optionalString(row, 'area_label'),
    locationTimezone: _optionalString(row, 'location_timezone'),
    imageMediaIds: _optionalStringList(row, 'image_media_ids'),
    requestRevision: _requirePositiveInt(
      row,
      'request_revision',
      '$context.request_revision',
    ),
    publishedAt: _optionalTimestamp(
      row,
      'published_at',
      '$context.published_at',
    ),
    acceptanceExpiresAt: _optionalTimestamp(
      row,
      'acceptance_expires_at',
      '$context.acceptance_expires_at',
    ),
    // Discovery completion additive fields. Absent on the legacy seller-leads
    // RPC, so an older server never fabricates a distance or match.
    distanceMiles: _optionalDouble(row, 'distance_miles'),
    matchPercent: _optionalInt(row, 'match_percent'),
    discoveryOpen: _optionalBool(row, 'discovery_open'),
    verifiedPurchaseCount: _optionalInt(row, 'verified_purchase_count'),
    lastCompletedItemLabel: _optionalString(row, 'last_completed_item_label'),
  );
}

/// Decodes `marketplace_discovery_leads` into the domain page, including
/// sort metadata, radius state and the explainable match reasons.
DiscoveryLeadPage decodeDiscoveryLeadPageJson(
  Map<String, Object?> json,
  String context,
) {
  final rows = decodeObjectList(json['items'], context);
  final items = <SellerLeadProjection>[];
  final reasons = <List<String>>[];
  for (var index = 0; index < rows.length; index++) {
    final rowContext = '$context.items[$index]';
    items.add(decodeLeadJson(rows[index], rowContext));
    reasons.add(_optionalStringList(rows[index], 'match_reasons'));
  }
  final cursor = json['next_cursor'];
  if (cursor != null && cursor is! String) {
    throw MarketplaceDecodeException('$context.next_cursor');
  }
  final sortWire = json['sort'];
  final sort = sortWire is String ? DiscoverySort.fromWire(sortWire) : null;
  if (sort == null) throw MarketplaceDecodeException('$context.sort');
  final radius = json['applied_radius_miles'];
  if (radius != null && radius is! num) {
    throw MarketplaceDecodeException('$context.applied_radius_miles');
  }
  final declared = json['declared_category_count'];
  if (declared != null && declared is! num) {
    throw MarketplaceDecodeException('$context.declared_category_count');
  }
  return DiscoveryLeadPage(
    items: items,
    nextCursor: cursor is String && cursor.trim().isNotEmpty ? cursor : null,
    sort: sort,
    appliedRadiusMiles: radius is num ? radius.toInt() : null,
    distanceAvailable: json['distance_available'] == true,
    manualAreaFallback: json['manual_area_fallback'] == true,
    declaredCategoryCount: declared is num ? declared.toInt() : 0,
    matchReasons: reasons,
  );
}

// ---------------------------------------------------------------------------
// Offers
// ---------------------------------------------------------------------------

OfferRevision decodeOfferRevisionJson(
  Map<String, Object?> row,
  String context,
) {
  final currency = _requireString(
    row,
    'currency_code',
    '$context.currency_code',
  );
  final placeChoice = placeChoiceFromWire(
    _requireString(row, 'place_choice', '$context.place_choice'),
    '$context.place_choice',
  );
  return OfferRevision(
    id: _requireString(row, 'id', '$context.id'),
    offerId: _requireString(row, 'offer_id', '$context.offer_id'),
    sequence: _requirePositiveInt(row, 'sequence', '$context.sequence'),
    terms: OfferTerms(
      price: Money(
        minorUnits: _requirePositiveInt(
          row,
          'price_minor',
          '$context.price_minor',
        ),
        currencyCode: currency,
      ),
      message: _requireString(
        row,
        'message',
        '$context.message',
        allowEmpty: true,
      ),
      imageMediaIds: _stringList(
        row['image_media_ids'] ?? const <Object?>[],
        '$context.image_media_ids',
      ),
      schedule: LocalSchedule(
        date: _localDate(
          _requireString(row, 'schedule_date', '$context.schedule_date'),
          '$context.schedule_date',
        ),
        startTime: _localTime(
          _requireString(row, 'schedule_time', '$context.schedule_time'),
          '$context.schedule_time',
        ),
        timezoneId: _requireString(
          row,
          'schedule_timezone',
          '$context.schedule_timezone',
        ),
        occurrence: _optionalOccurrence(row, '$context.schedule_occurrence'),
      ),
      place: MeetingPlace(
        choice: placeChoice,
        label: _optionalString(row, 'place_label'),
        address: _optionalString(row, 'place_address'),
        placeId: _optionalString(row, 'place_id'),
        latitude: decodePlaceCoordinate(row, 'place_latitude'),
        longitude: decodePlaceCoordinate(row, 'place_longitude'),
      ),
    ),
    status: offerRevisionStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    proposedByUserId: _requireString(
      row,
      'proposed_by_user_id',
      '$context.proposed_by_user_id',
    ),
    createdAt: _requireTimestamp(row, 'created_at', '$context.created_at'),
    resolvedUtcInstant: _optionalTimestamp(
      row,
      'schedule_utc_instant',
      '$context.schedule_utc_instant',
    ),
    resolvedUtcOffsetMinutes: _optionalInt(row, 'schedule_utc_offset_minutes'),
  );
}

RepeatedTimeOccurrence? _optionalOccurrence(
  Map<String, Object?> row,
  String context,
) {
  final value = row['schedule_occurrence'];
  if (value == null) return null;
  if (value is! String) throw MarketplaceDecodeException(context);
  return repeatedTimeOccurrenceFromWire(value, context);
}

Offer decodeOfferJson(Map<String, Object?> row, String context) {
  final revisions = <OfferRevision>[];
  final rawRevisions = row['revisions'];
  if (rawRevisions != null) {
    final rows = decodeObjectList(rawRevisions, context);
    for (var index = 0; index < rows.length; index++) {
      revisions.add(
        decodeOfferRevisionJson(rows[index], '$context.revisions[$index]'),
      );
    }
  }
  if (revisions.isEmpty) {
    throw MarketplaceDecodeException('$context.revisions');
  }
  return Offer(
    id: _requireString(row, 'id', '$context.id'),
    requestId: _requireString(row, 'request_id', '$context.request_id'),
    buyerUserId: _requireString(row, 'buyer_user_id', '$context.buyer_user_id'),
    sellerProfileId: _requireString(
      row,
      'seller_profile_id',
      '$context.seller_profile_id',
    ),
    sellerUserId: _requireString(
      row,
      'seller_user_id',
      '$context.seller_user_id',
    ),
    sellerDisplayName: _optionalString(row, 'seller_display_name'),
    requestTitle: _optionalString(row, 'request_title'),
    revisions: revisions,
    status: offerStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    acceptedRevisionId: _optionalString(row, 'accepted_revision_id'),
    conversationId: _optionalString(row, 'conversation_id'),
    purchaseSelected: _optionalBool(row, 'purchase_selected') ?? false,
    requestFirstAcceptedAt: _optionalTimestamp(
      row,
      'request_first_accepted_at',
      '$context.request_first_accepted_at',
    ),
    requestAcceptanceExpiresAt: _optionalTimestamp(
      row,
      'request_acceptance_expires_at',
      '$context.request_acceptance_expires_at',
    ),
    stamp: _stamp(row, context),
  );
}

// ---------------------------------------------------------------------------
// Store listings
// ---------------------------------------------------------------------------

StoreListing decodeStoreListingJson(Map<String, Object?> row, String context) {
  return StoreListing(
    id: _requireString(row, 'id', '$context.id'),
    sellerProfileId: _requireString(
      row,
      'seller_profile_id',
      '$context.seller_profile_id',
    ),
    sellerUserId: _requireString(
      row,
      'seller_user_id',
      '$context.seller_user_id',
    ),
    kind: listingKindFromWire(
      _requireString(row, 'kind', '$context.kind'),
      '$context.kind',
    ),
    title: _requireString(row, 'title', '$context.title'),
    description: _requireString(
      row,
      'description',
      '$context.description',
      allowEmpty: true,
    ),
    categoryLabel: _requireString(
      row,
      'category_label',
      '$context.category_label',
      allowEmpty: true,
    ),
    categoryId: _optionalString(row, 'category_id'),
    categoryAnswers: _categoryAnswers(row),
    priceLabel: _requireString(row, 'price_label', '$context.price_label'),
    serviceArea: _requireString(
      row,
      'service_area',
      '$context.service_area',
      allowEmpty: true,
    ),
    availability: _requireString(
      row,
      'availability',
      '$context.availability',
      allowEmpty: true,
    ),
    imageMediaIds: _stringList(
      row['image_media_ids'] ?? const <Object?>[],
      '$context.image_media_ids',
    ),
    status: listingStatusFromWire(
      _requireString(row, 'status', '$context.status'),
      '$context.status',
    ),
    moderationStatus: moderationStatusFromWire(
      _requireString(row, 'moderation_status', '$context.moderation_status'),
      '$context.moderation_status',
    ),
    stamp: _stamp(row, context),
    publishedAt: _optionalTimestamp(
      row,
      'published_at',
      '$context.published_at',
    ),
  );
}

PublicStoreListing decodePublicStoreListingJson(
  Map<String, Object?> row,
  String context,
) {
  return PublicStoreListing(
    id: _requireString(row, 'id', '$context.id'),
    sellerProfileId: _requireString(
      row,
      'seller_profile_id',
      '$context.seller_profile_id',
    ),
    kind: listingKindFromWire(
      _requireString(row, 'kind', '$context.kind'),
      '$context.kind',
    ),
    title: _requireString(row, 'title', '$context.title'),
    description: _requireString(
      row,
      'description',
      '$context.description',
      allowEmpty: true,
    ),
    categoryLabel: _requireString(
      row,
      'category_label',
      '$context.category_label',
      allowEmpty: true,
    ),
    categoryId: _optionalString(row, 'category_id'),
    categoryAnswers: _categoryAnswers(row),
    priceLabel: _requireString(row, 'price_label', '$context.price_label'),
    serviceArea: _requireString(
      row,
      'service_area',
      '$context.service_area',
      allowEmpty: true,
    ),
    availability: _requireString(
      row,
      'availability',
      '$context.availability',
      allowEmpty: true,
    ),
    imageMediaIds: _stringList(
      row['image_media_ids'] ?? const <Object?>[],
      '$context.image_media_ids',
    ),
    publishedAt: _optionalTimestamp(
      row,
      'published_at',
      '$context.published_at',
    ),
  );
}

StoreListingSummary decodeStoreSummaryJson(
  Map<String, Object?> row,
  String context,
) {
  return StoreListingSummary(
    draftCount: _requireInt(row, 'draft_count', '$context.draft_count'),
    activeCount: _requireInt(row, 'active_count', '$context.active_count'),
    pausedCount: _requireInt(row, 'paused_count', '$context.paused_count'),
    archivedCount: _requireInt(
      row,
      'archived_count',
      '$context.archived_count',
    ),
  );
}

/// The marketplace plan summary returned with the Store counts.
class MarketplacePlanStatus {
  MarketplacePlanStatus({
    required String planCode,
    required this.storeListingLimit,
  }) : planCode = planCode.trim();

  final String planCode;
  final int storeListingLimit;

  @override
  String toString() =>
      'MarketplacePlanStatus($planCode, storeLimit: $storeListingLimit)';
}

MarketplacePlanStatus decodePlanStatusJson(
  Map<String, Object?> row,
  String context,
) {
  return MarketplacePlanStatus(
    planCode: _requireString(row, 'plan_code', '$context.plan_code'),
    storeListingLimit: _requireInt(
      row,
      'store_listing_limit',
      '$context.store_listing_limit',
    ),
  );
}
