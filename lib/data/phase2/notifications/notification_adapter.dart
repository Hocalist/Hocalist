/// Notification inbox data adapter.
///
/// Uses the same authenticated RPC transport and session fencing as the
/// marketplace adapter: no table selects, no service-role pathway, and stale
/// session results are rejected.
library;

import '../../../domain/phase2/failures.dart';
import '../../../domain/phase2/notifications.dart';
import '../../../domain/phase2/profiles.dart';
import '../marketplace/marketplace_codecs.dart';
import '../marketplace/marketplace_error_mapper.dart';
import '../marketplace/marketplace_session.dart';
import '../marketplace/marketplace_transport.dart';
import 'notification_codecs.dart';

class NotificationDataAdapter {
  NotificationDataAdapter({
    required this.transport,
    required this.session,
    this.errorMapper = const MarketplaceErrorMapper(),
  });

  static const String schema = 'hocalist';

  static const RepositoryError _unauthenticated = PermissionDeniedError(
    action: 'authenticate',
    entityType: 'account_session',
  );
  static const RepositoryError _staleSession = PermissionDeniedError(
    action: 'session_changed',
    entityType: 'account_session',
  );

  final MarketplaceTransport transport;
  final MarketplaceSession session;
  final MarketplaceErrorMapper errorMapper;

  String? _captureIdentity() => session.currentUserId;

  bool _isStillCurrent(String userId) => session.currentUserId == userId;

  RepositoryResult<T> _failure<T>(RepositoryError error) =>
      RepositoryFailureResult(error);

  Future<RepositoryResult<Map<String, Object?>>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    final userId = _captureIdentity();
    if (userId == null) return _failure(_unauthenticated);
    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(schema: schema, function: function, params: params),
    );
    if (!_isStillCurrent(userId)) return _failure(_staleSession);
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
      return _failure(
        MalformedResponseError(operation: function, detail: error.detail),
      );
    }
  }

  Future<RepositoryResult<NotificationInboxPage>> fetchInbox({
    String? cursor,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      return _failure(
        const ValidationError(
          issues: [
            ValidationIssue(
              field: 'limit',
              code: 'invalid',
              message: 'Limit must be between 1 and 100.',
            ),
          ],
          debugMessage: 'notification inbox limit out of range',
        ),
      );
    }
    final result = await _rpc('notification_inbox', {
      'p_limit': limit,
      'p_cursor': cursor,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeNotificationInboxJson(result.valueOrNull!, 'notification_inbox'),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'notification_inbox',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<void>> markRead(String notificationId) async {
    final result = await _rpc('notification_mark_read', {
      'p_notification': notificationId,
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    return const RepositorySuccess<void>(null);
  }

  Future<RepositoryResult<int>> markAllRead() async {
    final result = await _rpc('notification_mark_all_read', const {});
    if (result.isFailure) return _failure(result.errorOrNull!);
    final marked = result.valueOrNull!['marked'];
    if (marked is! num || marked < 0) {
      return _failure(
        const MalformedResponseError(
          operation: 'notification_mark_all_read',
          detail: 'marked',
        ),
      );
    }
    return RepositorySuccess(marked.toInt());
  }

  Future<RepositoryResult<NotificationPreferencesRecord>>
  fetchPreferences() async {
    final result = await _rpc('notification_preferences', const {});
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeNotificationPreferencesJson(
          result.valueOrNull!,
          'notification_preferences',
        ),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'notification_preferences',
          detail: error.detail,
        ),
      );
    }
  }

  Future<RepositoryResult<NotificationPreferencesRecord>> updatePreferences({
    required NotificationPreferences preferences,
    required int expectedRevision,
    bool includeLeads = false,
  }) async {
    final result = await _rpc('notification_preferences_update', {
      'p_input': {
        'offers': preferences.offers,
        'messages': preferences.messages,
        'deals': preferences.deals,
        if (includeLeads) 'leads': preferences.leads,
        'safety': true,
        'expected_revision': expectedRevision,
      },
    });
    if (result.isFailure) return _failure(result.errorOrNull!);
    try {
      return RepositorySuccess(
        decodeNotificationPreferencesJson(
          result.valueOrNull!,
          'notification_preferences_update',
        ),
      );
    } on MarketplaceDecodeException catch (error) {
      return _failure(
        MalformedResponseError(
          operation: 'notification_preferences_update',
          detail: error.detail,
        ),
      );
    }
  }
}
