/// Maps transport failures to typed repository errors.
///
/// Known SQLSTATE codes and named `RAISE EXCEPTION` messages from drafts
/// 003/004 become typed failures. Unknown errors become a generic
/// [ServerError]; raw server messages and payloads are never propagated.
library;

import '../../../domain/phase2/phase2.dart';
import 'account_transport.dart';

/// Stateless mapper for account transport failures.
class AccountErrorMapper {
  const AccountErrorMapper();

  RepositoryError map(
    AccountTransportError error, {
    required String operation,
  }) {
    return switch (error.kind) {
      AccountTransportErrorKind.connectivity => NetworkError(
        retryable: error.retryable,
      ),
      AccountTransportErrorKind.unauthorized => const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      ),
      AccountTransportErrorKind.server => _mapServer(error, operation),
    };
  }

  RepositoryError _mapServer(AccountTransportError error, String operation) {
    final statusCode = error.statusCode;
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      // A 2xx response that the SDK could not decode is a contract mismatch,
      // not a server rejection.
      return MalformedResponseError(operation: operation, detail: 'payload');
    }
    final message = error.message ?? '';
    if (_has(message, 'revision_conflict')) {
      return const ConflictError(
        conflictCode: 'revision_conflict',
        debugMessage: 'The record revision is stale.',
      );
    }
    if (_has(message, 'idempotency_conflict')) {
      return const ConflictError(
        conflictCode: 'idempotency_conflict',
        debugMessage: 'The idempotency key was reused with different input.',
      );
    }
    if (_has(message, 'membership_exists')) {
      return const ConflictError(
        conflictCode: 'membership_exists',
        debugMessage: 'A membership for this role already exists.',
      );
    }
    if (_has(message, 'authentication_required')) {
      return const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      );
    }
    if (_has(message, 'onboarding_seed_required')) {
      return const PermissionDeniedError(
        action: 'onboarding_seed_required',
        entityType: 'account',
      );
    }
    if (_has(message, 'account_restricted')) {
      return const PermissionDeniedError(
        action: 'account_restricted',
        entityType: 'account',
      );
    }
    if (_has(message, 'profile_access_denied')) {
      return const PermissionDeniedError(
        action: 'profile_access_denied',
        entityType: 'role_profile',
      );
    }
    if (_has(message, 'contact_access_denied')) {
      return const PermissionDeniedError(
        action: 'contact_access_denied',
        entityType: 'private_contact',
      );
    }
    if (_has(message, 'invalid_display_name')) {
      return _invalidField('display_name');
    }
    if (_has(message, 'invalid_revision')) {
      return _invalidField('expected_revision');
    }
    if (_has(message, 'invalid_profile_id')) {
      return _invalidField('profile_id');
    }
    if (_has(message, 'invalid_radius')) {
      return _invalidField('service_radius_miles');
    }
    if (_has(message, 'seller_fields_on_buyer')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'service_radius_miles',
            code: ValidationCodes.invalidValue,
            message: 'Seller-only profile fields cannot be set on a buyer.',
          ),
        ],
        debugMessage: 'Seller-only fields were rejected for a buyer profile.',
      );
    }
    if (_has(message, 'invalid_role')) {
      return _invalidField('role');
    }
    if (_has(message, 'invalid_operation')) {
      return _invalidField('operation');
    }
    if (_has(message, 'invalid_command') ||
        _has(message, 'unknown_field') ||
        _has(message, 'invalid_field_type')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'request',
            code: ValidationCodes.invalidValue,
            message: 'The account request was rejected.',
          ),
        ],
        debugMessage: 'The account command payload was rejected.',
      );
    }

    switch (error.code) {
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
          action: 'account_command',
          entityType: 'account',
        );
      case '42501':
        return const PermissionDeniedError(
          action: 'account_command',
          entityType: 'account',
        );
      case '22023':
        return _invalidField('request');
      case '23514':
        return const ValidationError(
          issues: [
            ValidationIssue(
              field: 'value',
              code: ValidationCodes.outOfRange,
              message: 'A field violates an allowed length or range.',
            ),
          ],
          debugMessage: 'A column check rejected the value.',
        );
      case '23505':
        return const ConflictError(
          conflictCode: 'duplicate',
          debugMessage: 'The record already exists.',
        );
      case '23503':
        return const ValidationError(
          issues: [
            ValidationIssue(
              field: 'reference',
              code: ValidationCodes.invalidValue,
              message: 'A referenced record does not exist.',
            ),
          ],
          debugMessage: 'A foreign key reference was rejected.',
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
          message: 'The server rejected this field.',
        ),
      ],
    );
  }

  static bool _has(String message, String needle) => message.contains(needle);
}
