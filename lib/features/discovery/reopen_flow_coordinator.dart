/// Fenced reopen flow for the buyer recovery screen.
///
/// The server intent (request id, expected revision, operation key) is owned by
/// `RequestReopenIntentController` inside the repository. This coordinator owns
/// the *page* authority on top of it: it captures the account identity, the
/// destination epoch (bumped by every navigation event) and the selected
/// request id before awaiting, and only then may adopt the result, mutate the
/// recovery screen state or navigate. A delayed result for request A can never
/// overwrite a screen that now shows request B, a route instance that was left
/// and re-entered, or a replaced account session. Superseded results do not
/// discard the retained server intent, so a retry still replays the same key.
library;

import 'package:flutter/foundation.dart';

import '../../data/local_marketplace_repository.dart';
import '../../domain/phase2/requests.dart';

typedef ReopenCommand =
    Future<MarketplaceRequest> Function({
      required String requestId,
      required int expectedRevision,
    });

/// Truthful reopen feedback. A reopen is not a new post and must not reuse the
/// "Request posted." wording.
abstract final class ReopenFlowFeedback {
  static const String adopted =
      'Request reopened. Sellers can respond again.';
  static const String superseded =
      'Request reopened. It will appear in your requests.';
}

/// Outcome of one fenced reopen attempt.
sealed class ReopenFlowOutcome {
  const ReopenFlowOutcome();
}

/// The result belongs to the destination that is still current; the caller may
/// adopt it, update the selected request and navigate.
final class ReopenFlowAdopted extends ReopenFlowOutcome {
  const ReopenFlowAdopted(this.request);

  final MarketplaceRequest request;
}

/// A server-confirmed reopen for the same account whose destination or selected
/// request changed while it was in flight. The authoritative state is already
/// in the request cache, so the caller must not adopt, mutate the recovery
/// screen or navigate; a truthful background confirmation may be shown.
final class ReopenFlowSuperseded extends ReopenFlowOutcome {
  const ReopenFlowSuperseded(this.request);

  final MarketplaceRequest request;
}

/// A stale outcome that carries no confirmed same-account success: the account
/// session was replaced, the coordinator was disposed before the command could
/// be dispatched, or a late failure/unknown result arrived after the
/// destination or selected request changed. The page must stay silent; showing
/// success copy or an old-account error here would be a fabrication.
final class ReopenFlowStale extends ReopenFlowOutcome {
  const ReopenFlowStale();
}

/// The command failed for the still-current destination.
final class ReopenFlowFailed extends ReopenFlowOutcome {
  const ReopenFlowFailed(this.message, {required this.uncertain});

  final String message;

  /// True when the outcome is unknown and the retained intent should be retried
  /// with the same request id, revision and key.
  final bool uncertain;
}

/// Page feedback for one outcome. `null` means the page must stay silent:
/// stale failures, replaced accounts and current failures render their own
/// coordinator error state instead of a success message.
String? reopenPageFeedback(ReopenFlowOutcome outcome) => switch (outcome) {
  ReopenFlowAdopted() => ReopenFlowFeedback.adopted,
  ReopenFlowSuperseded() => ReopenFlowFeedback.superseded,
  ReopenFlowStale() => null,
  ReopenFlowFailed() => null,
};

/// True only when the page may adopt the record and navigate.
bool reopenPageMayAdopt(ReopenFlowOutcome outcome) =>
    outcome is ReopenFlowAdopted;

class ReopenFlowCoordinator extends ChangeNotifier {
  ReopenFlowCoordinator({
    required this.reopen,
    required this.sessionUserId,
    required this.destinationEpoch,
    required this.selectedRequestId,
    this.discardServerIntent,
  });

  /// Persists the reopen through the repository's retained intent.
  final ReopenCommand reopen;

  /// Current account identity; a change supersedes every in-flight attempt.
  final String? Function() sessionUserId;

  /// Monotonic destination generation for page actions. Every navigation event
  /// bumps it, so leaving and re-entering the same route is a new destination.
  final int Function() destinationEpoch;

  /// Currently selected request id, when one is explicitly selected.
  final String? Function() selectedRequestId;

  /// Abandons the repository's retained server intent on explicit discard.
  final VoidCallback? discardServerIntent;

  bool _busy = false;
  bool _disposed = false;
  String? _error;
  bool _uncertain = false;

  bool get busy => _busy;

  /// User-safe failure for the current destination, if any.
  String? get error => _error;

  bool get uncertain => _uncertain;

  /// Clears the retained feedback without touching the server intent.
  void clearFeedback() {
    if (_disposed || (_error == null && !_uncertain)) return;
    _error = null;
    _uncertain = false;
    notifyListeners();
  }

  /// Explicitly abandons the retained server intent and clears feedback. A
  /// later attempt starts a new server intent with a new key.
  void discard() {
    if (_disposed) return;
    discardServerIntent?.call();
    _error = null;
    _uncertain = false;
    notifyListeners();
  }

  Future<ReopenFlowOutcome> reopenRequest({
    required String requestId,
    required int expectedRevision,
  }) async {
    // No dispatch, no confirmed success: stale, and the page stays silent.
    if (_disposed || _busy) return const ReopenFlowStale();
    final session = sessionUserId();
    final epoch = destinationEpoch();
    _busy = true;
    _error = null;
    _uncertain = false;
    notifyListeners();
    try {
      final request = await reopen(
        requestId: requestId,
        expectedRevision: expectedRevision,
      );
      if (_disposed || sessionUserId() != session) {
        return const ReopenFlowStale();
      }
      if (!_isSameDestination(epoch, requestId)) {
        return ReopenFlowSuperseded(request);
      }
      _error = null;
      _uncertain = false;
      return ReopenFlowAdopted(request);
    } on StoreBackendException catch (error) {
      // The same authority predicate gates success and failure: a stale or
      // differently-selected failure must not write an error into the current
      // screen.
      if (!_isCurrent(session, epoch) || !_isSelected(requestId)) {
        return const ReopenFlowStale();
      }
      _error = error.message;
      _uncertain = error.ambiguous;
      return ReopenFlowFailed(error.message, uncertain: error.ambiguous);
    } finally {
      // The busy flag is global to this coordinator and only one attempt can be
      // in flight, so clearing it here cannot clobber a newer attempt. A stale
      // failure never reaches this point with state writes because the catch
      // returned early.
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool _isSelected(String requestId) {
    final selected = selectedRequestId();
    return selected == null || selected == requestId;
  }

  bool _isSameDestination(int epoch, String requestId) =>
      destinationEpoch() == epoch && _isSelected(requestId);

  bool _isCurrent(String? session, int epoch) =>
      !_disposed && sessionUserId() == session && destinationEpoch() == epoch;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
