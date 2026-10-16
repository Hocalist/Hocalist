/// Maps chat transport failures to typed repository errors.
///
/// Known SQLSTATE codes and named `RAISE EXCEPTION` messages from draft 010
/// become typed failures. Unknown errors become a generic [ServerError]; raw
/// server messages, message text and participant values are never propagated.
library;

import '../../../domain/phase2/failures.dart';
import 'chat_transport.dart';

class ChatErrorMapper {
  const ChatErrorMapper();

  RepositoryError map(ChatTransportError error, {required String operation}) {
    return switch (error.kind) {
      ChatTransportErrorKind.connectivity => NetworkError(
        retryable: error.retryable,
      ),
      ChatTransportErrorKind.unauthorized => const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      ),
      ChatTransportErrorKind.server => _mapServer(error, operation),
    };
  }

  RepositoryError _mapServer(ChatTransportError error, String operation) {
    final statusCode = error.statusCode;
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      return MalformedResponseError(operation: operation, detail: 'payload');
    }
    final message = error.message ?? '';
    if (_has(message, 'conversation_blocked')) {
      return const PermissionDeniedError(
        action: 'conversation_blocked',
        entityType: 'conversation',
      );
    }
    if (_has(message, 'conversation_access_denied')) {
      return const PermissionDeniedError(
        action: 'conversation_access_denied',
        entityType: 'conversation',
      );
    }
    if (_has(message, 'account_restricted')) {
      return const PermissionDeniedError(
        action: 'account_restricted',
        entityType: 'account',
      );
    }
    if (_has(message, 'role_not_active')) {
      return const PermissionDeniedError(
        action: 'role_not_active',
        entityType: 'membership',
      );
    }
    if (_has(message, 'authentication_required')) {
      return const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      );
    }
    if (_has(message, 'conversation_closed')) {
      return const ConflictError(
        conflictCode: 'conversation_closed',
        debugMessage: 'The conversation is closed.',
      );
    }
    if (_has(message, 'idempotency_conflict')) {
      return const ConflictError(
        conflictCode: 'idempotency_conflict',
        debugMessage: 'The retry key was reused with a different payload.',
      );
    }
    if (_has(message, 'invalid_cursor')) {
      return _invalidField('cursor');
    }
    if (_has(message, 'invalid_field: p_query') ||
        _has(message, 'invalid_field: p_page_size')) {
      return _invalidField('query');
    }
    if (_has(message, 'invalid_message')) {
      return _invalidField('message');
    }
    if (_has(message, 'invalid_origin') ||
        _has(message, 'invalid_subject') ||
        _has(message, 'invalid_participants')) {
      return _invalidField('conversation');
    }

    switch (error.code) {
      case 'PGRST202':
        return const ServerError(
          operation: 'backend_unavailable',
          statusCode: 404,
        );
      case '401':
      case 'PGRST301':
      case 'PGRST302':
      case 'PGRST303':
        return const PermissionDeniedError(
          action: 'authenticate',
          entityType: 'account_session',
        );
      case '403':
        return const PermissionDeniedError(
          action: 'conversation',
          entityType: 'conversation',
        );
      case '404':
        return const NotFoundError(
          entityType: 'conversation',
          entityId: 'requested',
        );
      case '42501':
        return const PermissionDeniedError(
          action: 'conversation',
          entityType: 'conversation',
        );
      case '22023':
        return _invalidField('request');
      case '23514':
      case '23503':
        return const ValidationError(
          issues: [
            ValidationIssue(
              field: 'value',
              code: ValidationCodes.invalidValue,
              message: 'A chat value violates an allowed length or reference.',
            ),
          ],
          debugMessage: 'A chat column check or reference rejected the value.',
        );
      default:
        return ServerError(operation: operation, statusCode: error.statusCode);
    }
  }

  static ValidationError _invalidField(String field) {
    return ValidationError(
      issues: [
        ValidationIssue(
          field: field,
          code: ValidationCodes.invalidValue,
          message: 'The server rejected this chat value.',
        ),
      ],
    );
  }

  static bool _has(String message, String needle) => message.contains(needle);
}
