/// Real-mode buyer request backend for the approved create/edit forms.
///
/// Bridges the form's complete [RequestDraft] to the marketplace request RPCs.
/// The screens keep their approved layout; this adapter owns mapping, paging
/// and user-safe error messages. Status, revision and timestamps stay
/// server-owned, and every write keeps the caller's operation key so a retried
/// submit remains one intent.
library;

import '../../../domain/phase2/common.dart';
import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/requests.dart';
import '../../local_marketplace_repository.dart';
import 'marketplace_adapter.dart';

/// Optional reopen capability of a requests backend. The repository detects it
/// instead of assuming every backend can reopen; older backends stay valid.
abstract interface class MarketplaceRequestReopenBackend {
  Future<MarketplaceRequest> reopenRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  });
}

class Phase2MarketplaceRequestsBackend
    implements MarketplaceRequestsBackend, MarketplaceRequestReopenBackend {
  Phase2MarketplaceRequestsBackend({
    required this.adapter,
    required this.buyerUserId,
  });

  final MarketplaceDataAdapter adapter;
  final String buyerUserId;

  @override
  Future<List<CatalogueCategoryOption>> loadCategories() async {
    final options = <CatalogueCategoryOption>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await adapter.fetchCategories(
        includeRetired: true,
        page: PageQuery(limit: 200, cursor: cursor),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        throw StoreBackendException(
          _message(error),
          ambiguous: _isAmbiguous(error),
        );
      }
      final slice = result.valueOrNull!;
      for (final category in slice.items) {
        options.add(
          CatalogueCategoryOption(
            id: category.id,
            label: category.label,
            scope: category.scope.name,
            status: category.status.name,
          ),
        );
      }
      cursor = slice.nextCursor;
      if (cursor == null) break;
    }
    return options;
  }

  @override
  Future<List<MarketplaceRequest>> loadBuyerRequests() async {
    final requests = <MarketplaceRequest>[];
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final result = await adapter.fetchBuyerRequests(
        buyerUserId: buyerUserId,
        page: PageQuery(limit: 50, cursor: cursor),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        throw StoreBackendException(
          _message(error),
          ambiguous: _isAmbiguous(error),
        );
      }
      final slice = result.valueOrNull!;
      requests.addAll(slice.items);
      cursor = slice.nextCursor;
      if (cursor == null) break;
    }
    return requests;
  }

  @override
  Future<MarketplaceRequest> createRequest({
    required RequestDraft draft,
    required String operationKey,
  }) async {
    final result = await adapter.createRequest(
      CreateRequestCommand(draft: draft, idempotencyKey: operationKey),
    );
    return _require(result);
  }

  @override
  Future<MarketplaceRequest> updateRequest({
    required String requestId,
    required int expectedRevision,
    required RequestDraft draft,
    required String operationKey,
  }) async {
    final result = await adapter.updateRequest(
      UpdateRequestCommand(
        requestId: requestId,
        expectedRevision: expectedRevision,
        draft: draft,
        idempotencyKey: operationKey,
      ),
    );
    return _require(result);
  }

  @override
  Future<MarketplaceRequest> closeRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await adapter.closeRequest(
      CloseRequestCommand(
        requestId: requestId,
        expectedRevision: expectedRevision,
        idempotencyKey: operationKey,
      ),
    );
    return _require(result);
  }

  /// Reopens a closed request through the reviewed `request.reopen` command.
  @override
  Future<MarketplaceRequest> reopenRequest({
    required String requestId,
    required int expectedRevision,
    required String operationKey,
  }) async {
    final result = await adapter.reopenRequest(
      ReopenRequestCommand(
        requestId: requestId,
        expectedRevision: expectedRevision,
        idempotencyKey: operationKey,
      ),
    );
    return _require(result);
  }

  MarketplaceRequest _require(RepositoryResult<MarketplaceRequest> result) {
    if (result.isFailure) {
      final error = result.errorOrNull!;
      throw StoreBackendException(
        _message(error),
        ambiguous: _isAmbiguous(error),
      );
    }
    return result.valueOrNull!;
  }

  /// An outcome that may have committed despite the reported failure. These
  /// must be retried with the same operation key and payload.
  bool _isAmbiguous(RepositoryError? error) {
    if (error == null) return false;
    return switch (error.kind) {
      RepositoryFailureKind.network ||
      RepositoryFailureKind.malformedResponse => true,
      RepositoryFailureKind.server =>
        error is ServerError &&
            (error.statusCode == null || error.statusCode! >= 500),
      _ => false,
    };
  }

  String _message(RepositoryError? error) {
    if (error == null) {
      return 'Your request could not be saved. Try again.';
    }
    return switch (error.kind) {
      RepositoryFailureKind.limitExceeded =>
        'Your plan limit was reached for this action.',
      RepositoryFailureKind.permissionDenied =>
        'You cannot change this request.',
      RepositoryFailureKind.notFound => 'This request is no longer available.',
      RepositoryFailureKind.network =>
        'The request could not be confirmed. Retry to check it safely.',
      RepositoryFailureKind.conflict =>
        'This request changed on another device. Refresh and try again.',
      RepositoryFailureKind.validation =>
        'Check the request details and try again.',
      _ => 'Your request could not be saved. Try again.',
    };
  }
}
