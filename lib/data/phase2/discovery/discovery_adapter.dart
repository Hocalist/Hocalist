/// Discovery, Hocatrends, consent and enquiry adapters over the reviewed
/// `discovery_completion` RPCs.
///
/// Identity comes from the injected session; caller-supplied ids are checked
/// against it. All reads use the authenticated RPC boundary; there are no
/// table selects and no service-role path. Decoded projections never include
/// buyer coordinates, addresses or contacts.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/discovery.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/requests.dart';
import '../marketplace/marketplace_codecs.dart';
import '../marketplace/marketplace_error_mapper.dart';
import '../marketplace/marketplace_session.dart';
import '../marketplace/marketplace_transport.dart';

class DiscoveryDecodeException implements Exception {
  const DiscoveryDecodeException(this.detail);

  final String detail;

  @override
  String toString() => 'DiscoveryDecodeException($detail)';
}

class DiscoveryDataAdapter {
  DiscoveryDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  static const String schema = 'hocalist';

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  String? _captureIdentity() => session.currentUserId;

  bool _isStillCurrent(String userId) => session.currentUserId == userId;

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  Future<RepositoryResult<Map<String, Object?>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return const RepositoryFailureResult(_unauthenticated);
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: schema, function: function, params: params),
    );
    if (!_isStillCurrent(userId)) {
      return const RepositoryFailureResult(_staleSession);
    }
    return switch (response) {
      MarketplaceTransportData(:final data) => _decode(function, data),
      MarketplaceTransportError() => RepositoryFailureResult(
        errorMapper.map(response, operation: function),
      ),
    };
  }

  RepositoryResult<Map<String, Object?>> _decode(
    String function,
    Object? data,
  ) {
    try {
      return RepositorySuccess(decodeObject(data, function));
    } on MarketplaceDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<T>> _read<T>(
    String function,
    Map<String, Object?> params,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, params);
    if (result.isFailure) return RepositoryFailureResult(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, function));
    } on DiscoveryDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    } on MarketplaceDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<T>> _keyedCommand<T>(
    String function,
    String key,
    Map<String, Object?> input,
    T Function(Map<String, Object?> row, String context) decode,
  ) async {
    final result = await _rpc(function, {'p_key': key, 'p_input': input});
    if (result.isFailure) return RepositoryFailureResult(result.errorOrNull!);
    try {
      return RepositorySuccess(decode(result.valueOrNull!, function));
    } on DiscoveryDecodeException catch (error) {
      return RepositoryFailureResult(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Origin and discovery leads
  // -------------------------------------------------------------------------

  Future<RepositoryResult<SellerDiscoveryOrigin>> fetchOrigin() => _read(
    'discovery_origin_json',
    const {},
    _decodeOrigin,
  );

  Future<RepositoryResult<SellerDiscoveryOrigin>> setOrigin({
    required SellerDiscoveryOriginInput input,
    required String operationKey,
  }) => _keyedCommand(
    'discovery_origin_set',
    operationKey,
    input.toWire(),
    _decodeOrigin,
  );

  Future<RepositoryResult<DiscoveryLeadPage>> fetchLeadPage({
    required DiscoveryLeadFilter filter,
    PageQuery page = PageQuery.standard,
  }) => _read(
    'marketplace_discovery_leads',
    {
      'p_kind': filter.kind?.name,
      'p_category': filter.categoryId,
      'p_area': filter.areaLabel,
      'p_limit': page.limit,
      'p_cursor': page.cursor,
      'p_sort': filter.sort.wire,
      'p_radius_miles': filter.radiusMiles,
      'p_query': filter.query,
      'p_budget_min_minor': filter.budgetMinimumMinor,
      'p_budget_max_minor': filter.budgetMaximumMinor,
    },
    _decodeLeadPage,
  );

  Future<RepositoryResult<RecommendedLeadsView>> fetchRecommendedLeads({
    int limit = 6,
  }) => _read(
    'marketplace_recommended_leads',
    {'p_limit': limit},
    _decodeRecommended,
  );

  Future<RepositoryResult<Set<String>>> fetchSellerOutcomes({
    int limit = 100,
  }) async {
    final result = await _read(
      'marketplace_seller_outcomes',
      {'p_limit': limit},
      (row, context) {
        final rows = decodeObjectList(row['items'], context);
        final ids = <String>{};
        for (var index = 0; index < rows.length; index++) {
          final id = rows[index]['meeting_id'];
          if (id is! String || id.trim().isEmpty) {
            throw DiscoveryDecodeException('$context.items[$index].meeting_id');
          }
          ids.add(id);
        }
        return ids;
      },
    );
    return result;
  }

  // -------------------------------------------------------------------------
  // Trends, winners and consent
  // -------------------------------------------------------------------------

  Future<RepositoryResult<HocatrendsProjection>> fetchTrends({
    int limit = 10,
  }) => _read(
    'hocatrends_trends',
    {'p_limit': limit},
    _decodeTrends,
  );

  Future<RepositoryResult<WinnersView>> fetchWinners({int limit = 10}) =>
      _read('hocatrends_winners', {'p_limit': limit}, _decodeWinners);

  Future<RepositoryResult<HocatrendsSellerResults>> fetchTopicSellers(
    String topicId, {
    int limit = 20,
  }) => _read(
    'hocatrends_topic_sellers',
    {'p_topic': topicId, 'p_limit': limit},
    _decodeTopicSellers,
  );

  Future<RepositoryResult<BuyerPublicProfileConsent>> fetchBuyerConsent() =>
      _read(
        'buyer_public_profile_consent_json',
        const {},
        _decodeConsent,
      );

  Future<RepositoryResult<BuyerPublicProfileConsent>> setBuyerConsent({
    required BuyerPublicProfileConsent consent,
    required String operationKey,
  }) => _keyedCommand(
    'buyer_public_profile_consent_set',
    operationKey,
    {
      'is_public': consent.isPublic,
      'show_display_name': consent.showDisplayName,
      'show_area': consent.showArea,
      'show_categories': consent.showCategories,
    },
    _decodeConsent,
  );

  Future<RepositoryResult<PublicBuyerProfile>> fetchBuyerPublicProfile(
    String profileId,
  ) => _read(
    'buyer_public_profile',
    {'p_profile': profileId},
    _decodePublicBuyerProfile,
  );

  // -------------------------------------------------------------------------
  // Origin-isolated enquiry opening
  // -------------------------------------------------------------------------

  Future<RepositoryResult<OpenedDiscoveryEnquiry>> openEnquiry({
    required DiscoveryEnquiryOrigin origin,
    required String subjectId,
    String? sellerProfileId,
    required String operationKey,
  }) {
    final input = <String, Object?>{
      'origin': origin.wire,
      if (origin == DiscoveryEnquiryOrigin.storeListing)
        'listing_id': subjectId
      else ...{
        'topic_id': subjectId,
        'seller_profile_id': ?sellerProfileId,
      },
    };
    return _keyedCommand(
      'discovery_open_enquiry',
      operationKey,
      input,
      _decodeEnquiry,
    );
  }

  // -------------------------------------------------------------------------
  // Decoders
  // -------------------------------------------------------------------------

  SellerDiscoveryOrigin _decodeOrigin(
    Map<String, Object?> row,
    String context,
  ) {
    final configured = row['configured'];
    if (configured is! bool) {
      throw DiscoveryDecodeException('$context.configured');
    }
    if (!configured) return const SellerDiscoveryOrigin.notConfigured();
    final area = row['area_label'];
    final radius = row['radius_miles'];
    final revision = row['revision'];
    if (area != null && area is! String) {
      throw DiscoveryDecodeException('$context.area_label');
    }
    if (radius is! int || radius < 1 || radius > 500) {
      throw DiscoveryDecodeException('$context.radius_miles');
    }
    if (row['coordinates_present'] is! bool) {
      throw DiscoveryDecodeException('$context.coordinates_present');
    }
    if (revision is! int || revision < 1) {
      throw DiscoveryDecodeException('$context.revision');
    }
    return SellerDiscoveryOrigin(
      configured: true,
      areaLabel: area as String?,
      coordinatesPresent: row['coordinates_present']! as bool,
      radiusMiles: radius,
      revision: revision,
    );
  }

  DiscoveryLeadPage _decodeLeadPage(
    Map<String, Object?> row,
    String context,
  ) => decodeDiscoveryLeadPageJson(row, context);

  RecommendedLeadsView _decodeRecommended(
    Map<String, Object?> row,
    String context,
  ) {
    final rows = decodeObjectList(row['items'], context);
    final items = <SellerLeadProjection>[];
    final reasons = <List<String>>[];
    for (var index = 0; index < rows.length; index++) {
      final rowContext = '$context.items[$index]';
      items.add(decodeLeadJson(rows[index], rowContext));
      final rawReasons = rows[index]['match_reasons'];
      if (rawReasons != null && rawReasons is! List) {
        throw DiscoveryDecodeException('$rowContext.match_reasons');
      }
      reasons.add(
        rawReasons == null
            ? const []
            : List<String>.unmodifiable(
                (rawReasons as List).map((entry) {
                  if (entry is! String) {
                    throw DiscoveryDecodeException(
                      '$rowContext.match_reasons',
                    );
                  }
                  return entry;
                }),
              ),
      );
    }
    final basisRow = row['basis'];
    if (basisRow != null && basisRow is! Map) {
      throw DiscoveryDecodeException('$context.basis');
    }
    final basisMap = basisRow == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(basisRow as Map);
    final labels = decodeObjectList(
      basisMap['declared_categories'] ?? const <Object?>[],
      '$context.basis.declared_categories',
    );
    final basis = RecommendedLeadsBasis(
      declaredCategoryLabels: labels
          .map((entry) => entry['label'])
          .whereType<String>()
          .toList(growable: false),
      areaLabel: basisMap['area_label'] is String
          ? basisMap['area_label']! as String
          : null,
      radiusMiles: basisMap['radius_miles'] is int
          ? basisMap['radius_miles']! as int
          : null,
    );
    final reason = row['unavailable_reason'];
    if (reason != null && reason is! String) {
      throw DiscoveryDecodeException('$context.unavailable_reason');
    }
    return RecommendedLeadsView(
      items: items,
      matchReasons: reasons,
      basis: basis,
      unavailableReason: reason as String?,
    );
  }

  HocatrendsProjection _decodeTrends(
    Map<String, Object?> row,
    String context,
  ) {
    final rows = decodeObjectList(row['items'], context);
    final items = <HocatrendsTopic>[];
    for (var index = 0; index < rows.length; index++) {
      final entry = rows[index];
      final entryContext = '$context.items[$index]';
      final rank = entry['rank'];
      final categoryId = entry['category_id'];
      final label = entry['label'];
      final openRequests = entry['open_requests'];
      final competing = entry['competing_sellers'];
      final purchases = entry['confirmed_purchases'];
      final buyers = entry['participating_buyers'];
      final percent = entry['percent'];
      final competition = entry['competition'];
      final copy = entry['activity_copy'];
      if (rank is! int ||
          categoryId is! String ||
          label is! String ||
          openRequests is! int ||
          competing is! int ||
          purchases is! int ||
          buyers is! int ||
          percent is! int ||
          competition is! String ||
          copy is! String) {
        throw DiscoveryDecodeException(entryContext);
      }
      if (percent < 0 || percent > 100) {
        throw DiscoveryDecodeException('$entryContext.percent');
      }
      items.add(
        HocatrendsTopic(
          rank: rank,
          categoryId: categoryId,
          label: label,
          openRequests: openRequests,
          competingSellers: competing,
          confirmedPurchases: purchases,
          participatingBuyers: buyers,
          percent: percent,
          competition: competition,
          activityCopy: copy,
        ),
      );
    }
    final window = row['window_days'];
    final total = row['open_request_total'];
    if (window is! int || total is! int) {
      throw DiscoveryDecodeException('$context.window');
    }
    return HocatrendsProjection(
      items: items,
      windowDays: window,
      openRequestTotal: total,
    );
  }

  WinnersView _decodeWinners(Map<String, Object?> row, String context) {
    final rows = decodeObjectList(row['items'], context);
    final items = <WinnerEntry>[];
    for (var index = 0; index < rows.length; index++) {
      final entry = rows[index];
      final entryContext = '$context.items[$index]';
      final outcomeId = entry['outcome_id'];
      final buyerLabel = entry['buyer_label'];
      final category = entry['category_label'];
      final area = entry['area_label'];
      if (outcomeId is! String || buyerLabel is! String) {
        throw DiscoveryDecodeException(entryContext);
      }
      if (category != null && category is! String) {
        throw DiscoveryDecodeException('$entryContext.category_label');
      }
      if (area != null && area is! String) {
        throw DiscoveryDecodeException('$entryContext.area_label');
      }
      items.add(
        WinnerEntry(
          outcomeId: outcomeId,
          buyerLabel: buyerLabel,
          categoryLabel: category as String?,
          areaLabel: area as String?,
        ),
      );
    }
    final window = row['window_days'];
    if (window is! int) throw DiscoveryDecodeException('$context.window');
    return WinnersView(items: items, windowDays: window);
  }

  HocatrendsSellerResults _decodeTopicSellers(
    Map<String, Object?> row,
    String context,
  ) {
    final topicId = row['topic_id'];
    if (topicId is! String) {
      throw DiscoveryDecodeException('$context.topic_id');
    }
    final rows = decodeObjectList(row['items'], context);
    final items = <HocatrendsSellerView>[];
    for (var index = 0; index < rows.length; index++) {
      final entry = rows[index];
      final entryContext = '$context.items[$index]';
      final profileId = entry['seller_profile_id'];
      final displayName = entry['display_name'];
      final area = entry['area_label'];
      final listingId = entry['listing_id'];
      final listingTitle = entry['listing_title'];
      final priceLabel = entry['price_label'];
      final ratingSum = entry['rating_sum'];
      final ratingCount = entry['rating_count'];
      final deals = entry['completed_deals'];
      if (profileId is! String ||
          displayName is! String ||
          ratingSum is! int ||
          ratingCount is! int ||
          deals is! int) {
        throw DiscoveryDecodeException(entryContext);
      }
      if ((area != null && area is! String) ||
          (listingId != null && listingId is! String) ||
          (listingTitle != null && listingTitle is! String) ||
          (priceLabel != null && priceLabel is! String)) {
        throw DiscoveryDecodeException(entryContext);
      }
      items.add(
        HocatrendsSellerView(
          sellerProfileId: profileId,
          displayName: displayName,
          areaLabel: area as String?,
          listingId: listingId as String?,
          listingTitle: listingTitle as String?,
          priceLabel: priceLabel as String?,
          ratingSum: ratingSum,
          ratingCount: ratingCount,
          completedDeals: deals,
        ),
      );
    }
    return HocatrendsSellerResults(topicId: topicId, items: items);
  }

  BuyerPublicProfileConsent _decodeConsent(
    Map<String, Object?> row,
    String context,
  ) {
    final isPublic = row['is_public'];
    final showName = row['show_display_name'];
    final showArea = row['show_area'];
    final showCategories = row['show_categories'];
    final revision = row['revision'];
    if (isPublic is! bool ||
        showName is! bool ||
        showArea is! bool ||
        showCategories is! bool ||
        revision is! int) {
      throw DiscoveryDecodeException(context);
    }
    return BuyerPublicProfileConsent(
      isPublic: isPublic,
      showDisplayName: showName,
      showArea: showArea,
      showCategories: showCategories,
      revision: revision,
    );
  }

  PublicBuyerProfile _decodePublicBuyerProfile(
    Map<String, Object?> row,
    String context,
  ) {
    final available = row['available'];
    if (available is! bool) {
      throw DiscoveryDecodeException('$context.available');
    }
    if (!available) {
      return PublicBuyerProfile(
        available: false,
        profileId: row['profile_id'] is String
            ? row['profile_id']! as String
            : null,
      );
    }
    final profileId = row['profile_id'];
    final displayName = row['display_name'];
    final area = row['area_label'];
    final memberSince = row['member_since'];
    final purchases = row['verified_purchase_count'];
    if (profileId is! String ||
        (displayName != null && displayName is! String) ||
        (area != null && area is! String) ||
        purchases is! int) {
      throw DiscoveryDecodeException(context);
    }
    return PublicBuyerProfile(
      available: true,
      profileId: profileId,
      displayName: displayName as String?,
      areaLabel: area as String?,
      memberSince: memberSince is String
          ? DateTime.tryParse(memberSince)?.toUtc()
          : null,
      verifiedPurchaseCount: purchases,
    );
  }

  OpenedDiscoveryEnquiry _decodeEnquiry(
    Map<String, Object?> row,
    String context,
  ) {
    final conversationId = row['conversation_id'];
    final origin = row['origin'];
    final subjectId = row['subject_id'];
    if (conversationId is! String ||
        origin is! String ||
        subjectId is! String) {
      throw DiscoveryDecodeException(context);
    }
    final decodedOrigin = DiscoveryEnquiryOrigin.fromWire(origin);
    if (decodedOrigin == null) {
      throw DiscoveryDecodeException('$context.origin');
    }
    return OpenedDiscoveryEnquiry(
      conversationId: conversationId,
      origin: decodedOrigin,
      subjectId: subjectId,
    );
  }
}

/// Seller-owned discovery origin as the form needs it.
class SellerDiscoveryOrigin {
  const SellerDiscoveryOrigin({
    required this.configured,
    this.areaLabel,
    this.coordinatesPresent = false,
    this.radiusMiles,
    this.revision = 0,
  });

  const SellerDiscoveryOrigin.notConfigured()
    : configured = false,
      areaLabel = null,
      coordinatesPresent = false,
      radiusMiles = null,
      revision = 0;

  final bool configured;
  final String? areaLabel;
  final bool coordinatesPresent;
  final int? radiusMiles;
  final int revision;
}

/// Writable discovery origin values. Coordinates are the seller's own
/// approximate origin; they are never the buyer's.
class SellerDiscoveryOriginInput {
  const SellerDiscoveryOriginInput({
    this.areaLabel,
    this.latitude,
    this.longitude,
    this.radiusMiles = 25,
  });

  final String? areaLabel;
  final double? latitude;
  final double? longitude;
  final int radiusMiles;

  Map<String, Object?> toWire() => {
    'area_label': areaLabel,
    'latitude': latitude,
    'longitude': longitude,
    'radius_miles': radiusMiles,
  };
}
