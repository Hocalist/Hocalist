/// Real-mode leads backend for the approved seller Leads screen.
///
/// Implements the legacy single-page seam and the paged discovery seam. The
/// page uses the paged seam when available so server cursors, filters and
/// sorts are not dropped.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/discovery.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/requests.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

/// Paged, server-filtered seller discovery. Older single-page backends stay
/// valid; the screen detects this capability instead of assuming it.
abstract interface class MarketplacePagedLeadsBackend {
  Future<DiscoveryLeadPage> loadLeadPage({
    required DiscoveryLeadFilter filter,
    String? cursor,
    int limit,
  });
}

class Phase2MarketplaceLeadsBackend
    implements MarketplaceLeadsBackend, MarketplacePagedLeadsBackend {
  Phase2MarketplaceLeadsBackend({
    required this.adapter,
    required this.sellerUserId,
  });

  final MarketplaceDataAdapter adapter;
  final String sellerUserId;

  @override
  Future<List<SellerLeadProjection>> loadLeads() async {
    final result = await adapter.fetchSellerLeads(sellerUserId: sellerUserId);
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: error.kind == RepositoryFailureKind.network,
      );
    }
    return result.valueOrNull!.items;
  }

  @override
  Future<DiscoveryLeadPage> loadLeadPage({
    required DiscoveryLeadFilter filter,
    String? cursor,
    int limit = 20,
  }) async {
    final result = await adapter.fetchDiscoveryLeadPage(
      kind: filter.kind,
      categoryId: filter.categoryId,
      areaLabel: filter.areaLabel,
      query: filter.query,
      budgetMinimumMinor: filter.budgetMinimumMinor,
      budgetMaximumMinor: filter.budgetMaximumMinor,
      sort: filter.sort,
      radiusMiles: filter.radiusMiles,
      page: PageQuery(cursor: cursor, limit: limit),
    );
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: error.kind == RepositoryFailureKind.network,
      );
    }
    return result.valueOrNull!;
  }

  String _message(RepositoryError error) => switch (error.kind) {
    RepositoryFailureKind.network => 'Check your connection and try again.',
    RepositoryFailureKind.permissionDenied =>
      'Your seller access is not active.',
    _ => 'Could not load buyer requests. Pull to retry.',
  };
}
