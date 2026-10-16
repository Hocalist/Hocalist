/// Single unresolved reopen intent for one repository/session.
///
/// A reopen is retried with the same client-owned operation key and expected
/// revision until it is definitively resolved or explicitly discarded, so a
/// lost acknowledgement cannot become a second, differently-keyed intent. The
/// controller also fences delayed results: after [discard] or [dispose] a
/// late response is never applied, and overlapping intents are refused.
library;

import '../../../domain/phase2/requests.dart';
import '../../local_marketplace_repository.dart';

typedef RequestReopenCall =
    Future<MarketplaceRequest> Function({
      required String requestId,
      required int expectedRevision,
      required String operationKey,
    });

typedef RequestReopenApply = void Function(MarketplaceRequest request);

class RequestReopenIntentController {
  RequestReopenIntentController({
    required this.reopen,
    required this.apply,
    String Function(String prefix)? operationKeyFactory,
  }) : operationKeyFactory =
           operationKeyFactory ?? LocalMarketplaceRepository.newStoreOperationKey;

  final RequestReopenCall reopen;
  final RequestReopenApply apply;
  final String Function(String prefix) operationKeyFactory;

  String? _requestId;
  int? _expectedRevision;
  String? _operationKey;
  bool _pending = false;
  bool _disposed = false;
  int _generation = 0;

  /// True while an unresolved intent is retained for retry.
  bool get hasPendingIntent => _operationKey != null;

  String? get pendingRequestId => _requestId;

  int? get pendingExpectedRevision => _expectedRevision;

  /// Abandons the retained intent. An in-flight result is fenced and will not
  /// be applied; the next call starts a new intent with a new key.
  void discard() {
    if (_disposed) return;
    _clearIntent();
    _generation += 1;
  }

  /// Fences this controller permanently (repository disposed or the account
  /// session replaced).
  void dispose() {
    _disposed = true;
    _generation += 1;
    _pending = false;
    _clearIntent();
  }

  Future<MarketplaceRequest> run({
    required String requestId,
    required int expectedRevision,
  }) async {
    if (_disposed) {
      throw const StoreBackendException(
        'The account changed before the reopen completed.',
        ambiguous: true,
      );
    }
    if (_pending) {
      throw const StoreBackendException(
        'A reopen for this request is already in progress.',
      );
    }
    final sameIntent =
        _requestId == requestId &&
        _expectedRevision == expectedRevision &&
        _operationKey != null;
    final key = sameIntent
        ? _operationKey!
        : operationKeyFactory('request-reopen');
    _requestId = requestId;
    _expectedRevision = expectedRevision;
    _operationKey = key;
    final generation = ++_generation;
    _pending = true;
    try {
      final reopened = await reopen(
        requestId: requestId,
        expectedRevision: expectedRevision,
        operationKey: key,
      );
      if (_disposed || generation != _generation || _operationKey != key) {
        // The destination or session changed while the command was in flight;
        // the result is deliberately not applied.
        throw const StoreBackendException(
          'The reopen result was discarded because the account or intent '
          'changed. Refresh to see the authoritative state.',
          ambiguous: true,
        );
      }
      apply(reopened);
      _clearIntent();
      return reopened;
    } on StoreBackendException catch (error) {
      if (!error.ambiguous && !_disposed && generation == _generation) {
        // A definitive server rejection resolves the intent; a later attempt
        // with changed local state starts a new intent.
        _clearIntent();
      }
      rethrow;
    } finally {
      // Only one run can be in flight (guarded by _pending), so the flag is
      // always released here; a discarded in-flight call still holds it until
      // it settles, which prevents overlapping server intents.
      _pending = false;
    }
  }

  void _clearIntent() {
    _requestId = null;
    _expectedRevision = null;
    _operationKey = null;
  }
}

