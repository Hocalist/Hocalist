/// Discovery contracts for the approved seller Leads, Hocatrends and
/// Store/Hocatrends enquiry surfaces.
///
/// These types describe server-authorized filters, cursor pages, explainable
/// matching and the gated public projections. They never carry buyer
/// coordinates, addresses or contacts: the server projection excludes them and
/// these models have no field for them.
library;

import 'common.dart';
import 'requests.dart';

/// Server-authorized ordering for seller discovery.
enum DiscoverySort {
  newest('newest'),
  recommended('recommended'),
  closest('closest'),
  budget('budget');

  const DiscoverySort(this.wire);

  /// Wire value accepted by `marketplace_discovery_leads`.
  final String wire;

  static DiscoverySort? fromWire(String wire) {
    for (final value in DiscoverySort.values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// Filters selected on the seller Leads screen. Values are inputs; which
/// requests a seller may see and how matches are computed stays server policy.
class DiscoveryLeadFilter {
  DiscoveryLeadFilter({
    this.kind,
    String? categoryId,
    String? areaLabel,
    String? query,
    this.budgetMinimumMinor,
    this.budgetMaximumMinor,
    this.sort = DiscoverySort.newest,
    this.radiusMiles,
  }) : categoryId = optionalNonBlank(categoryId, 'categoryId'),
       areaLabel = optionalNonBlank(areaLabel, 'areaLabel'),
       query = optionalNonBlank(query, 'query') {
    if (budgetMinimumMinor != null && budgetMinimumMinor! < 0) {
      throw ArgumentError.value(
        budgetMinimumMinor,
        'budgetMinimumMinor',
        'must not be negative',
      );
    }
    if (budgetMaximumMinor != null && budgetMaximumMinor! < 0) {
      throw ArgumentError.value(
        budgetMaximumMinor,
        'budgetMaximumMinor',
        'must not be negative',
      );
    }
    if (radiusMiles != null && (radiusMiles! < 1 || radiusMiles! > 500)) {
      throw ArgumentError.value(
        radiusMiles,
        'radiusMiles',
        'must be between 1 and 500',
      );
    }
  }

  final RequestKind? kind;
  final String? categoryId;
  final String? areaLabel;
  final String? query;
  final int? budgetMinimumMinor;
  final int? budgetMaximumMinor;
  final DiscoverySort sort;
  final int? radiusMiles;

  bool get isEmpty =>
      kind == null &&
      categoryId == null &&
      areaLabel == null &&
      query == null &&
      budgetMinimumMinor == null &&
      budgetMaximumMinor == null &&
      sort == DiscoverySort.newest &&
      radiusMiles == null;
}

/// One authoritative discovery page. [nextCursor] is the server cursor for the
/// same filter and sort; it is null on the last page.
class DiscoveryLeadPage {
  DiscoveryLeadPage({
    required List<SellerLeadProjection> items,
    this.nextCursor,
    required this.sort,
    this.appliedRadiusMiles,
    this.distanceAvailable = false,
    this.manualAreaFallback = false,
    this.declaredCategoryCount = 0,
    List<List<String>> matchReasons = const [],
  }) : items = List<SellerLeadProjection>.unmodifiable(items),
       matchReasons = List<List<String>>.unmodifiable(
         matchReasons.map(List<String>.unmodifiable),
       );

  final List<SellerLeadProjection> items;
  final String? nextCursor;
  final DiscoverySort sort;

  /// Explainable server reasons for each item, position-aligned with [items].
  final List<List<String>> matchReasons;

  /// Radius actually applied by the server, when one was configured.
  final int? appliedRadiusMiles;

  /// True when the seller origin carries coordinates, so distances are real.
  final bool distanceAvailable;

  /// True when the server fell back to manual area-label matching because no
  /// coordinates are available. Distances are absent in that state.
  final bool manualAreaFallback;

  final int declaredCategoryCount;

  bool get hasMore => nextCursor != null;
}

/// Seller matching basis used by the recommended-leads projection.
class RecommendedLeadsBasis {
  const RecommendedLeadsBasis({
    this.declaredCategoryLabels = const [],
    this.areaLabel,
    this.radiusMiles,
  });

  final List<String> declaredCategoryLabels;
  final String? areaLabel;
  final int? radiusMiles;
}

/// Result of `marketplace_recommended_leads`.
class RecommendedLeadsView {
  RecommendedLeadsView({
    required List<SellerLeadProjection> items,
    this.basis = const RecommendedLeadsBasis(),
    this.unavailableReason,
    List<List<String>> matchReasons = const [],
  }) : items = List<SellerLeadProjection>.unmodifiable(items),
       matchReasons = List<List<String>>.unmodifiable(
         matchReasons.map(List<String>.unmodifiable),
       );

  final List<SellerLeadProjection> items;

  /// Explainable server reasons per item, aligned with [items].
  final List<List<String>> matchReasons;
  final RecommendedLeadsBasis basis;

  /// `no_matching_basis` when the seller has no declared categories, area or
  /// radius; `no_eligible_matches` when the basis exists but nothing matches.
  final String? unavailableReason;

  bool get hasBasis =>
      basis.declaredCategoryLabels.isNotEmpty ||
      (basis.areaLabel?.trim().isNotEmpty ?? false) ||
      basis.radiusMiles != null;
}

/// One ranked Hocatrends topic built from verified marketplace activity.
class HocatrendsTopic {
  const HocatrendsTopic({
    required this.rank,
    required this.categoryId,
    required this.label,
    required this.openRequests,
    required this.competingSellers,
    required this.confirmedPurchases,
    required this.participatingBuyers,
    required this.percent,
    required this.competition,
    required this.activityCopy,
  });

  final int rank;
  final String categoryId;
  final String label;
  final int openRequests;
  final int competingSellers;
  final int confirmedPurchases;
  final int participatingBuyers;

  /// Share of currently open requests in this topic (0-100).
  final int percent;

  /// `Very High`, `High`, `Medium` or `New`, derived from real seller counts.
  final String competition;
  final String activityCopy;

  bool get hasVerifiedActivity =>
      openRequests > 0 || competingSellers > 0 || confirmedPurchases > 0;
}

/// Signed-in Hocatrends projection.
class HocatrendsProjection {
  HocatrendsProjection({
    required List<HocatrendsTopic> items,
    this.windowDays = 30,
    this.openRequestTotal = 0,
  }) : items = List<HocatrendsTopic>.unmodifiable(items);

  final List<HocatrendsTopic> items;
  final int windowDays;
  final int openRequestTotal;

  bool get isEmpty => items.isEmpty;
}

/// One verified purchase in the Winners projection. Buyer identity and area
/// are masked unless the buyer explicitly opted in.
class WinnerEntry {
  const WinnerEntry({
    required this.outcomeId,
    this.categoryLabel,
    required this.buyerLabel,
    this.areaLabel,
  });

  final String outcomeId;
  final String? categoryLabel;
  final String buyerLabel;
  final String? areaLabel;
}

/// Winners projection result.
class WinnersView {
  WinnersView({required List<WinnerEntry> items, this.windowDays = 30})
    : items = List<WinnerEntry>.unmodifiable(items);

  final List<WinnerEntry> items;
  final int windowDays;

  bool get isEmpty => items.isEmpty;
}

/// One seller in the Hocatrends topic results. Public facts only: no exact
/// address, contacts or private offers.
class HocatrendsSellerView {
  const HocatrendsSellerView({
    required this.sellerProfileId,
    required this.displayName,
    this.areaLabel,
    this.listingId,
    this.listingTitle,
    this.priceLabel,
    this.ratingSum = 0,
    this.ratingCount = 0,
    this.completedDeals = 0,
  });

  final String sellerProfileId;
  final String displayName;
  final String? areaLabel;
  final String? listingId;
  final String? listingTitle;
  final String? priceLabel;
  final int ratingSum;
  final int ratingCount;
  final int completedDeals;

  double? get averageRating =>
      ratingCount == 0 ? null : ratingSum / ratingCount;
}

/// Hocatrends topic seller results.
class HocatrendsSellerResults {
  HocatrendsSellerResults({
    required this.topicId,
    required List<HocatrendsSellerView> items,
  }) : items = List<HocatrendsSellerView>.unmodifiable(items);

  final String topicId;
  final List<HocatrendsSellerView> items;
}

/// Store or Hocatrends enquiry origin.
enum DiscoveryEnquiryOrigin {
  storeListing('store_listing'),
  hocatrendsEnquiry('hocatrends_enquiry');

  const DiscoveryEnquiryOrigin(this.wire);

  final String wire;

  static DiscoveryEnquiryOrigin? fromWire(String wire) {
    for (final value in DiscoveryEnquiryOrigin.values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// Authoritative result of opening a discovery enquiry.
class OpenedDiscoveryEnquiry {
  const OpenedDiscoveryEnquiry({
    required this.conversationId,
    required this.origin,
    required this.subjectId,
  });

  final String conversationId;
  final DiscoveryEnquiryOrigin origin;
  final String subjectId;
}

/// Seller account-health projection derived from the reviewed trust reads.
/// This is a manual-review status, never a computed score.
class SellerAccountHealthView {
  const SellerAccountHealthView({
    required this.emailVerified,
    required this.phoneVerified,
    required this.reviewStatus,
    this.restrictions = const [],
    this.loaded = true,
  });

  const SellerAccountHealthView.unavailable()
    : emailVerified = false,
      phoneVerified = false,
      reviewStatus = 'not_submitted',
      restrictions = const [],
      loaded = false;

  final bool emailVerified;
  final bool phoneVerified;

  /// Latest reviewed evidence status: `not_submitted`, `pending`, `approved`
  /// or `rejected`.
  final String reviewStatus;

  final List<SellerHealthRestriction> restrictions;
  final bool loaded;

  bool get hasActiveRestriction => restrictions.any((row) => row.canAppeal);
}

/// One recorded restriction with its reason and appeal route.
class SellerHealthRestriction {
  const SellerHealthRestriction({
    required this.id,
    required this.scope,
    required this.reason,
    this.appealId,
    this.appealStatus,
  });

  final String id;
  final String scope;
  final String reason;
  final String? appealId;
  final String? appealStatus;

  bool get canAppeal => appealId == null;
}

/// Buyer public-profile consent state. Closed by default.
class BuyerPublicProfileConsent {
  const BuyerPublicProfileConsent({
    this.isPublic = false,
    this.showDisplayName = false,
    this.showArea = false,
    this.showCategories = false,
    this.revision = 0,
  });

  final bool isPublic;
  final bool showDisplayName;
  final bool showArea;
  final bool showCategories;
  final int revision;
}

/// Consented public buyer projection. [available] is false unless the buyer
/// explicitly opted in.
class PublicBuyerProfile {
  const PublicBuyerProfile({
    required this.available,
    this.profileId,
    this.displayName,
    this.areaLabel,
    this.memberSince,
    this.verifiedPurchaseCount = 0,
  });

  final bool available;
  final String? profileId;
  final String? displayName;
  final String? areaLabel;
  final DateTime? memberSince;
  final int verifiedPurchaseCount;
}
