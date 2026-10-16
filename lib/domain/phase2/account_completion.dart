/// Account-completion domain types (package 01-accounts).
///
/// These cover the seller category selection used by the profile editor and
/// the authorized evidence metadata the admin package consumes. Existing
/// domain files stay unchanged; import this file directly or re-export it from
/// the coordinator's phase2 barrel.
library;

import 'catalogue.dart';
import 'common.dart';

/// One catalogue category offered to a seller profile.
class SellerCategoryOption {
  SellerCategoryOption({
    required String id,
    required String label,
    String? slug,
    required this.scope,
    required this.status,
    required this.selectable,
    required this.sortOrder,
  }) : id = requireNonBlank(id, 'id'),
       label = requireNonBlank(label, 'label'),
       slug = optionalNonBlank(slug, 'slug') {
    if (sortOrder < 0) {
      throw ArgumentError.value(sortOrder, 'sortOrder', 'must not be negative');
    }
    if (selectable && status != CatalogueEntryStatus.active) {
      throw ArgumentError('only active categories are selectable');
    }
  }

  final String id;
  final String label;
  final String? slug;
  final CatalogueScope scope;

  /// Server-owned status. A retired selected category stays visible with
  /// [selectable] false until the seller explicitly replaces it.
  final CatalogueEntryStatus status;
  final bool selectable;
  final int sortOrder;

  bool get isRetired => status == CatalogueEntryStatus.retired;

  @override
  String toString() =>
      'SellerCategoryOption($id, ${status.name}, selectable: $selectable)';
}

/// One authoritative seller category read.
class SellerCategorySelection {
  SellerCategorySelection({
    required String membershipId,
    required this.revision,
    required List<SellerCategoryOption> selected,
    required List<SellerCategoryOption> available,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId'),
       selected = List<SellerCategoryOption>.unmodifiable(selected),
       available = List<SellerCategoryOption>.unmodifiable(available) {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final String membershipId;

  /// Role-profile revision the selection was read at.
  final int revision;
  final List<SellerCategoryOption> selected;
  final List<SellerCategoryOption> available;

  /// Retired choices still attached to the profile.
  List<SellerCategoryOption> get retiredSelected =>
      selected.where((option) => option.isRetired).toList(growable: false);

  @override
  String toString() =>
      'SellerCategorySelection($membershipId, revision: $revision, '
      'selected: ${selected.length}, available: ${available.length})';
}

/// Outcome of one category update, carrying the new profile revision.
class SellerCategoryUpdateResult {
  SellerCategoryUpdateResult({
    required String membershipId,
    required this.revision,
    required List<String> categoryIds,
  }) : membershipId = requireNonBlank(membershipId, 'membershipId'),
       categoryIds = List<String>.unmodifiable(categoryIds) {
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be at least 1');
    }
  }

  final String membershipId;
  final int revision;
  final List<String> categoryIds;

  @override
  String toString() =>
      'SellerCategoryUpdateResult($membershipId, revision: $revision, '
      'categories: ${categoryIds.length})';
}
