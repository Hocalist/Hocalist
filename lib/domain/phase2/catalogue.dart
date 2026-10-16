/// Admin-managed catalogue contracts for Phase 2.
///
/// Categories, option groups and options are server-owned configuration.
/// Admin commands here are proposals for the coordinating schema work; the
/// client only reads active entries for request and Store forms. Retiring an
/// entry sets a status instead of deleting it so historical requests and
/// listings keep their meaning.
///
/// No production category values, attributes or commercial rules are
/// hardcoded in this library. Values come from the backend.
library;

import 'common.dart';

/// Which request/listing kind a catalogue entry applies to.
enum CatalogueScope {
  product,
  service,
  both;

  /// True when a product listing may select this category. The server still
  /// validates the selection; this is a display/filter helper.
  bool get supportsProduct => this != CatalogueScope.service;

  /// True when a service listing may select this category. The server still
  /// validates the selection; this is a display/filter helper.
  bool get supportsService => this != CatalogueScope.product;
}

/// Server-owned lifecycle of a catalogue entry.
///
/// Retired entries stay readable for historical records but are not offered
/// for new selections unless an admin read includes them.
enum CatalogueEntryStatus { active, retired }

/// Whether an option group accepts one or several options.
enum CatalogueSelectionMode { single, multiple }

/// Entry kind addressed by a shared status command.
enum CatalogueEntryType { category, optionGroup, option }

/// One admin-managed category in the Hocalist catalogue.
class CatalogueCategory {
  CatalogueCategory({
    required String id,
    String? parentId,
    required String label,
    String? slug,
    required this.scope,
    required this.status,
    required this.sortOrder,
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       parentId = optionalNonBlank(parentId, 'parentId'),
       label = requireNonBlank(label, 'label'),
       slug = optionalNonBlank(slug, 'slug') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
    if (parentId == id) {
      throw ArgumentError('a category cannot be its own parent');
    }
  }

  final String id;

  /// Parent category id for a hierarchy, when the backend uses one.
  final String? parentId;

  /// Admin-managed display label.
  final String label;

  /// Optional stable URL/slug identifier.
  final String? slug;

  final CatalogueScope scope;

  /// Server-owned status; never set by a client command.
  final CatalogueEntryStatus status;

  /// Admin-managed ordering within the same parent and scope.
  final int sortOrder;

  /// Server-owned revision and timestamps.
  final RecordStamp stamp;

  bool get isActive => status == CatalogueEntryStatus.active;

  CatalogueCategory copyWith({
    String? parentId,
    bool clearParent = false,
    String? label,
    String? slug,
    bool clearSlug = false,
    CatalogueScope? scope,
    CatalogueEntryStatus? status,
    int? sortOrder,
    RecordStamp? stamp,
  }) {
    if (clearParent && parentId != null) {
      throw ArgumentError('parentId and clearParent are mutually exclusive');
    }
    if (clearSlug && slug != null) {
      throw ArgumentError('slug and clearSlug are mutually exclusive');
    }
    return CatalogueCategory(
      id: id,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      label: label ?? this.label,
      slug: clearSlug ? null : (slug ?? this.slug),
      scope: scope ?? this.scope,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      stamp: stamp ?? this.stamp,
    );
  }

  @override
  String toString() =>
      'CatalogueCategory($id, ${scope.name}, ${status.name}, '
      'order: $sortOrder)';
}

/// A selectable group of options inside one category.
class CatalogueOptionGroup {
  CatalogueOptionGroup({
    required String id,
    required String categoryId,
    required String label,
    required this.selectionMode,
    this.isRequired = false,
    required this.status,
    required this.sortOrder,
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       categoryId = requireNonBlank(categoryId, 'categoryId'),
       label = requireNonBlank(label, 'label') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String id;
  final String categoryId;
  final String label;
  final CatalogueSelectionMode selectionMode;

  /// Whether a seller/buyer must choose an option from this group.
  final bool isRequired;

  final CatalogueEntryStatus status;
  final int sortOrder;
  final RecordStamp stamp;

  bool get isActive => status == CatalogueEntryStatus.active;

  CatalogueOptionGroup copyWith({
    String? label,
    CatalogueSelectionMode? selectionMode,
    bool? isRequired,
    CatalogueEntryStatus? status,
    int? sortOrder,
    RecordStamp? stamp,
  }) {
    return CatalogueOptionGroup(
      id: id,
      categoryId: categoryId,
      label: label ?? this.label,
      selectionMode: selectionMode ?? this.selectionMode,
      isRequired: isRequired ?? this.isRequired,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      stamp: stamp ?? this.stamp,
    );
  }

  @override
  String toString() =>
      'CatalogueOptionGroup($id, category: $categoryId, ${status.name}, '
      'options: ${selectionMode.name})';
}

/// One selectable option inside an option group.
class CatalogueOption {
  CatalogueOption({
    required String id,
    required String groupId,
    required String label,
    required this.status,
    required this.sortOrder,
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       groupId = requireNonBlank(groupId, 'groupId'),
       label = requireNonBlank(label, 'label') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String id;
  final String groupId;
  final String label;
  final CatalogueEntryStatus status;
  final int sortOrder;
  final RecordStamp stamp;

  bool get isActive => status == CatalogueEntryStatus.active;

  CatalogueOption copyWith({
    String? label,
    CatalogueEntryStatus? status,
    int? sortOrder,
    RecordStamp? stamp,
  }) {
    return CatalogueOption(
      id: id,
      groupId: groupId,
      label: label ?? this.label,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      stamp: stamp ?? this.stamp,
    );
  }

  @override
  String toString() => 'CatalogueOption($id, group: $groupId, ${status.name})';
}

/// One admin-managed location option.
///
/// Location values are backend configuration; no production market list is
/// hardcoded in the client. [countryCode] is an ISO 3166-1 alpha-2 code.
class LocationEntry {
  LocationEntry({
    required String id,
    required String countryCode,
    String? region,
    String? city,
    required String label,
    String? timezoneId,
    required this.status,
    required this.sortOrder,
    required this.stamp,
  }) : id = requireNonBlank(id, 'id'),
       countryCode = countryCode.trim().toUpperCase(),
       region = optionalNonBlank(region, 'region'),
       city = optionalNonBlank(city, 'city'),
       label = requireNonBlank(label, 'label'),
       timezoneId = optionalNonBlank(timezoneId, 'timezoneId') {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(this.countryCode)) {
      throw ArgumentError.value(
        countryCode,
        'countryCode',
        'must be an ISO 3166-1 alpha-2 code',
      );
    }
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String id;
  final String countryCode;
  final String? region;
  final String? city;
  final String label;

  /// Named IANA meeting timezone for this location, or null while an admin has
  /// not resolved it. Never defaulted from the country or region.
  final String? timezoneId;

  final CatalogueEntryStatus status;
  final int sortOrder;
  final RecordStamp stamp;

  bool get isActive => status == CatalogueEntryStatus.active;

  bool get hasResolvedTimezone =>
      timezoneId != null && timezoneId!.trim().isNotEmpty;

  @override
  String toString() => 'LocationEntry($id, $countryCode, ${status.name})';
}

/// Creates a category with complete admin values.
class CreateCatalogueCategoryCommand {
  CreateCatalogueCategoryCommand({
    String? parentId,
    required String label,
    String? slug,
    required this.scope,
    this.sortOrder = 0,
    required String idempotencyKey,
  }) : parentId = optionalNonBlank(parentId, 'parentId'),
       label = requireNonBlank(label, 'label'),
       slug = optionalNonBlank(slug, 'slug'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String? parentId;
  final String label;
  final String? slug;
  final CatalogueScope scope;
  final int sortOrder;
  final String idempotencyKey;
}

/// Replaces all editable category values at an expected revision.
class UpdateCatalogueCategoryCommand {
  UpdateCatalogueCategoryCommand({
    required String categoryId,
    required this.expectedRevision,
    String? parentId,
    this.clearParent = false,
    required String label,
    String? slug,
    this.clearSlug = false,
    required this.scope,
    required this.sortOrder,
    required String idempotencyKey,
  }) : categoryId = requireNonBlank(categoryId, 'categoryId'),
       parentId = optionalNonBlank(parentId, 'parentId'),
       label = requireNonBlank(label, 'label'),
       slug = optionalNonBlank(slug, 'slug'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (clearParent && parentId != null) {
      throw ArgumentError('parentId and clearParent are mutually exclusive');
    }
    if (clearSlug && slug != null) {
      throw ArgumentError('slug and clearSlug are mutually exclusive');
    }
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String categoryId;
  final int expectedRevision;
  final String? parentId;
  final bool clearParent;
  final String label;
  final String? slug;
  final bool clearSlug;
  final CatalogueScope scope;
  final int sortOrder;
  final String idempotencyKey;
}

/// Creates an option group inside a category.
class CreateCatalogueOptionGroupCommand {
  CreateCatalogueOptionGroupCommand({
    required String categoryId,
    required String label,
    required this.selectionMode,
    this.isRequired = false,
    this.sortOrder = 0,
    required String idempotencyKey,
  }) : categoryId = requireNonBlank(categoryId, 'categoryId'),
       label = requireNonBlank(label, 'label'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String categoryId;
  final String label;
  final CatalogueSelectionMode selectionMode;
  final bool isRequired;
  final int sortOrder;
  final String idempotencyKey;
}

/// Replaces all editable option-group values at an expected revision.
class UpdateCatalogueOptionGroupCommand {
  UpdateCatalogueOptionGroupCommand({
    required String groupId,
    required this.expectedRevision,
    required String label,
    required this.selectionMode,
    required this.isRequired,
    required this.sortOrder,
    required String idempotencyKey,
  }) : groupId = requireNonBlank(groupId, 'groupId'),
       label = requireNonBlank(label, 'label'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String groupId;
  final int expectedRevision;
  final String label;
  final CatalogueSelectionMode selectionMode;
  final bool isRequired;
  final int sortOrder;
  final String idempotencyKey;
}

/// Creates an option inside an option group.
class CreateCatalogueOptionCommand {
  CreateCatalogueOptionCommand({
    required String groupId,
    required String label,
    this.sortOrder = 0,
    required String idempotencyKey,
  }) : groupId = requireNonBlank(groupId, 'groupId'),
       label = requireNonBlank(label, 'label'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String groupId;
  final String label;
  final int sortOrder;
  final String idempotencyKey;
}

/// Replaces all editable option values at an expected revision.
class UpdateCatalogueOptionCommand {
  UpdateCatalogueOptionCommand({
    required String optionId,
    required this.expectedRevision,
    required String label,
    required this.sortOrder,
    required String idempotencyKey,
  }) : optionId = requireNonBlank(optionId, 'optionId'),
       label = requireNonBlank(label, 'label'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
  }

  final String optionId;
  final int expectedRevision;
  final String label;
  final int sortOrder;
  final String idempotencyKey;
}

/// Result of activating or retiring a catalogue entry.
class CatalogueEntryStatusResult {
  CatalogueEntryStatusResult({
    required this.entryType,
    required String entryId,
    required this.status,
    required this.stamp,
  }) : entryId = requireNonBlank(entryId, 'entryId');

  final CatalogueEntryType entryType;
  final String entryId;
  final CatalogueEntryStatus status;
  final RecordStamp stamp;

  @override
  String toString() =>
      'CatalogueEntryStatusResult(${entryType.name}, $entryId, '
      '${status.name})';
}

/// Activates or retires one catalogue entry.
///
/// Retiring keeps the entry readable for historical requests and listings.
/// The server re-checks admin authorization; the client never decides it.
class SetCatalogueEntryStatusCommand {
  SetCatalogueEntryStatusCommand({
    required this.entryType,
    required String entryId,
    required this.expectedRevision,
    required this.status,
    required String idempotencyKey,
  }) : entryId = requireNonBlank(entryId, 'entryId'),
       idempotencyKey = requireNonBlank(idempotencyKey, 'idempotencyKey') {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be at least 1',
      );
    }
  }

  final CatalogueEntryType entryType;
  final String entryId;
  final int expectedRevision;
  final CatalogueEntryStatus status;
  final String idempotencyKey;
}
