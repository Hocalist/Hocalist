/// Page-facing discovery backends: recommended leads, seller outcomes,
/// Hocatrends/Winners projections, buyer consent and origin-isolated enquiry
/// opening.
///
/// Failures are surfaced as [StoreBackendException] with an `ambiguous` flag so
/// retries reuse the same intent key. Nothing here fabricates data when the
/// server projection is empty.
library;

import '../../../domain/phase2/discovery.dart';
import '../../../domain/phase2/customers.dart';
import '../../../domain/phase2/failures.dart';
import '../../local_marketplace_repository.dart';
import 'discovery_adapter.dart';

/// Seller-home recommended leads plus their declared matching basis.
abstract interface class MarketplaceRecommendedLeadsBackend {
  Future<RecommendedLeadsView> loadRecommendedLeads();
}

/// Confirmed seller outcomes used to render the Meets completed state.
abstract interface class SellerMeetsOutcomeBackend {
  Future<Set<String>> loadConfirmedMeetingIds();
}

/// Hocatrends and Winners projections.
abstract interface class HocatrendsBackend {
  Future<HocatrendsProjection> loadTrends();

  Future<WinnersView> loadWinners();

  Future<HocatrendsSellerResults> loadTopicSellers(String topicId);
}

/// Origin-isolated Store/Hocatrends conversation opening.
abstract interface class DiscoveryEnquiryBackend {
  Future<OpenedDiscoveryEnquiry> openEnquiry({
    required DiscoveryEnquiryOrigin origin,
    required String subjectId,
    String? sellerProfileId,
    required String operationKey,
  });
}

/// Buyer public-profile consent reads and writes.
abstract interface class BuyerConsentBackend {
  Future<BuyerPublicProfileConsent> loadConsent();

  Future<BuyerPublicProfileConsent> setConsent({
    required BuyerPublicProfileConsent consent,
    required String operationKey,
  });

  Future<PublicBuyerProfile> loadPublicProfile(String profileId);
}

class Phase2DiscoveryBackend
    implements
        MarketplaceRecommendedLeadsBackend,
        SellerMeetsOutcomeBackend,
        HocatrendsBackend,
        DiscoveryEnquiryBackend,
        BuyerConsentBackend,
        SellerDiscoveryOriginBackend {
  Phase2DiscoveryBackend({
    required this.adapter,
    required this.identity,
  });

  final DiscoveryDataAdapter adapter;
  final String? Function() identity;

  Future<SellerCustomerList> loadCustomers() async {
    final result = await adapter.sellerCustomers();
    if (result.errorOrNull case PermissionDeniedError(action: 'contacts_plan_required')) {
      throw const StoreBackendException('Customers requires Pro or Elite.', code: 'contacts_plan_required');
    }
    if (result.isFailure) throw _exception(result.errorOrNull!, 'seller_customers');
    final row = result.valueOrNull!;
    if (row['insights_available'] is! bool || row['items'] is! List) {
      throw const StoreBackendException('Could not verify customer records.');
    }
    final items = <SellerCustomer>[];
    for (final raw in row['items'] as List) {
      if (raw is! Map || raw['buyer_id'] is! String || raw['display_name'] is! String ||
          raw['purchase_count'] is! int || (raw['purchase_count'] as int) < 1 ||
          raw['saved'] is! bool || raw['note'] is! String ||
          raw['last_purchase_at'] is! String || DateTime.tryParse(raw['last_purchase_at'] as String) == null) {
        throw const StoreBackendException('Could not verify customer records.');
      }
      items.add(SellerCustomer(buyerId: raw['buyer_id'] as String,
        displayName: raw['display_name'] as String, purchaseCount: raw['purchase_count'] as int,
        lastPurchaseAt: DateTime.parse(raw['last_purchase_at'] as String),
        saved: raw['saved'] as bool, note: raw['note'] as String));
    }
    return (insightsAvailable: row['insights_available'] as bool, items: List<SellerCustomer>.unmodifiable(items));
  }

  Future<void> saveCustomer(String buyerId, bool saved, String note) async {
    final result = await adapter.sellerCustomerSave(buyerId, saved, note);
    if (result.isFailure) throw _exception(result.errorOrNull!, 'seller_customer_save');
    final row = result.valueOrNull!;
    if (row['buyer_id'] != buyerId || row['saved'] != saved || row['note'] != note) {
      throw const StoreBackendException('Customer save was not confirmed.', ambiguous: true);
    }
  }

  Future<CustomerHistory> loadCustomerHistory(String buyerId) async {
    final result = await adapter.sellerCustomerInsights(buyerId);
    if (result.isFailure) throw _exception(result.errorOrNull!, 'seller_customer_insights');
    final row = result.valueOrNull!;
    final ended = row['concluded_requests'];
    final bought = row['confirmed_purchases'];
    final ongoing = row['ongoing_requests'];
    final percent = row['completion_percent'];
    if (row['buyer_id'] != buyerId || ended is! int || bought is! int || ongoing is! int ||
        ended < 0 || bought < 0 || ongoing < 0 || bought > ended ||
        (ended == 0 ? percent != null : percent is! num || percent < 0 || percent > 100)) {
      throw const StoreBackendException('Could not verify purchase history.');
    }
    return CustomerHistory(concludedRequests: ended, confirmedPurchases: bought,
      ongoingRequests: ongoing, completionPercent: (percent as num?)?.toDouble());
  }

  Future<({bool enabled, bool eligible})> hocatrendsOfferPreference(
    String offerId, {bool? enabled}
  ) async {
    final result = await adapter.hocatrendsOfferPreference(offerId, enabled: enabled);
    if (result.isFailure) throw _exception(result.errorOrNull!, 'hocatrends_preference');
    final row = result.valueOrNull!;
    if (row['offer_id'] != offerId || row['enabled'] is! bool || row['eligible'] is! bool) {
      throw const StoreBackendException('Could not verify this Hocatrends preference.');
    }
    return (enabled: row['enabled'] as bool, eligible: row['eligible'] as bool);
  }

  @override
  Future<RecommendedLeadsView> loadRecommendedLeads() async {
    final result = await adapter.fetchRecommendedLeads();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'recommended');
    return result.valueOrNull!;
  }

  @override
  Future<Set<String>> loadConfirmedMeetingIds() async {
    final result = await adapter.fetchSellerOutcomes();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'outcomes');
    return result.valueOrNull!;
  }

  @override
  Future<HocatrendsProjection> loadTrends() async {
    final result = await adapter.fetchTrends();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'trends');
    return result.valueOrNull!;
  }

  @override
  Future<WinnersView> loadWinners() async {
    final result = await adapter.fetchWinners();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'winners');
    return result.valueOrNull!;
  }

  @override
  Future<HocatrendsSellerResults> loadTopicSellers(String topicId) async {
    final result = await adapter.fetchTopicSellers(topicId);
    if (result.isFailure) throw _exception(result.errorOrNull!, 'seller results');
    return result.valueOrNull!;
  }

  @override
  Future<OpenedDiscoveryEnquiry> openEnquiry({
    required DiscoveryEnquiryOrigin origin,
    required String subjectId,
    String? sellerProfileId,
    required String operationKey,
  }) async {
    final result = await adapter.openEnquiry(
      origin: origin,
      subjectId: subjectId,
      sellerProfileId: sellerProfileId,
      operationKey: operationKey,
    );
    if (result.isFailure) throw _exception(result.errorOrNull!, 'enquiry');
    return result.valueOrNull!;
  }

  @override
  Future<BuyerPublicProfileConsent> loadConsent() async {
    final result = await adapter.fetchBuyerConsent();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'consent');
    return result.valueOrNull!;
  }

  @override
  Future<BuyerPublicProfileConsent> setConsent({
    required BuyerPublicProfileConsent consent,
    required String operationKey,
  }) async {
    final result = await adapter.setBuyerConsent(
      consent: consent,
      operationKey: operationKey,
    );
    if (result.isFailure) throw _exception(result.errorOrNull!, 'consent');
    return result.valueOrNull!;
  }

  @override
  Future<PublicBuyerProfile> loadPublicProfile(String profileId) async {
    final result = await adapter.fetchBuyerPublicProfile(profileId);
    if (result.isFailure) throw _exception(result.errorOrNull!, 'profile');
    return result.valueOrNull!;
  }

  @override
  Future<SellerDiscoveryOrigin> loadOrigin() async {
    final result = await adapter.fetchOrigin();
    if (result.isFailure) throw _exception(result.errorOrNull!, 'discovery area');
    return result.valueOrNull!;
  }

  @override
  Future<SellerDiscoveryOrigin> setOrigin({
    required SellerDiscoveryOriginInput input,
    required String operationKey,
  }) async {
    final result = await adapter.setOrigin(
      input: input,
      operationKey: operationKey,
    );
    if (result.isFailure) throw _exception(result.errorOrNull!, 'discovery area');
    return result.valueOrNull!;
  }

  StoreBackendException _exception(RepositoryError error, String scope) =>
      StoreBackendException(
        switch (error.kind) {
          RepositoryFailureKind.network =>
            'Check your connection and try again.',
          RepositoryFailureKind.permissionDenied =>
            'This $scope view is not available for your account.',
          RepositoryFailureKind.notFound => 'This $scope view is unavailable.',
          RepositoryFailureKind.conflict =>
            'That change conflicts with a newer server state. Please try again.',
          _ => 'Could not load $scope. Try again.',
        },
        ambiguous:
            error.kind == RepositoryFailureKind.network ||
            error.kind == RepositoryFailureKind.server ||
            error.kind == RepositoryFailureKind.malformedResponse,
      );
}

/// Reads the seller's discovery origin for display/settings.
abstract interface class SellerDiscoveryOriginBackend {
  Future<SellerDiscoveryOrigin> loadOrigin();

  Future<SellerDiscoveryOrigin> setOrigin({
    required SellerDiscoveryOriginInput input,
    required String operationKey,
  });
}

