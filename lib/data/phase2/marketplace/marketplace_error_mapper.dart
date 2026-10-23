/// Maps marketplace transport failures to typed repository errors.
///
/// Known SQLSTATE codes and named `RAISE EXCEPTION` messages from draft 020
/// become typed failures. Unknown errors become a generic [ServerError]; raw
/// server messages, request text and addresses are never propagated.
library;

import '../../../domain/phase2/failures.dart';
import 'marketplace_transport.dart';

class MarketplaceErrorMapper {
  const MarketplaceErrorMapper();

  RepositoryError map(
    MarketplaceTransportError error, {
    required String operation,
  }) {
    return switch (error.kind) {
      MarketplaceTransportErrorKind.connectivity => NetworkError(
        retryable: error.retryable,
      ),
      MarketplaceTransportErrorKind.unauthorized => const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      ),
      MarketplaceTransportErrorKind.server => _mapServer(error, operation),
    };
  }

  RepositoryError _mapServer(
    MarketplaceTransportError error,
    String operation,
  ) {
    final statusCode = error.statusCode;
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      return MalformedResponseError(operation: operation, detail: 'payload');
    }
    final message = error.message ?? '';
    if (message.contains('active_request_limit_reached:')) {
      final limit = int.tryParse(RegExp(r'active_request_limit_reached:(\d+)').firstMatch(message)?.group(1) ?? '');
      return ValidationError(
        issues: [ValidationIssue(field: 'request', code: 'active_request_limit_reached',
          message: limit == null ? 'You have reached your active request limit. Close a request before adding another.'
              : 'You have reached the limit of $limit active requests. Close a request before adding another.')],
        debugMessage: 'The buyer has reached the configured active request limit.',
      );
    }
    if (_has(message, 'request_access_denied')) {
      return const PermissionDeniedError(
        action: 'request_access_denied',
        entityType: 'request',
      );
    }
    if (_has(message, 'offer_access_denied')) {
      return const PermissionDeniedError(
        action: 'offer_access_denied',
        entityType: 'offer',
      );
    }
    if (_has(message, 'listing_access_denied')) {
      return const PermissionDeniedError(
        action: 'listing_access_denied',
        entityType: 'store_listing',
      );
    }
    if (_has(message, 'admin_required')) {
      return const PermissionDeniedError(
        action: 'admin_required',
        entityType: 'platform_admin',
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
    if (_has(message, 'meeting_access_denied')) {
      return const PermissionDeniedError(
        action: 'meeting_access_denied',
        entityType: 'meeting',
      );
    }
    if (_has(message, 'meeting_not_found')) {
      return const NotFoundError(entityType: 'meeting', entityId: 'requested');
    }
    if (_has(message, 'authentication_required')) {
      return const PermissionDeniedError(
        action: 'authenticate',
        entityType: 'account_session',
      );
    }
    if (_has(message, 'request_not_found')) {
      return const NotFoundError(entityType: 'request', entityId: 'requested');
    }
    if (_has(message, 'offer_not_found')) {
      return const NotFoundError(entityType: 'offer', entityId: 'requested');
    }
    if (_has(message, 'listing_not_found')) {
      return const NotFoundError(
        entityType: 'store_listing',
        entityId: 'requested',
      );
    }
    if (_has(message, 'store_limit_exceeded')) {
      return const LimitExceededError(limitCode: 'store_listing');
    }
    if (_has(message, 'weekly_target_limit')) {
      return const LimitExceededError(limitCode: 'weekly_targets');
    }
    if (_has(message, 'targeting_fee_unconfigured')) {
      return const ConflictError(
        conflictCode: 'targeting_fee_unconfigured',
        debugMessage:
            'Targeting fees are not configured yet, so this offer cannot be accepted.',
      );
    }
    if (_has(message, 'insufficient_single_batch')) {
      return const ConflictError(
        conflictCode: 'insufficient_single_batch',
        debugMessage:
            'Your prepaid credits cannot cover this interaction. Add credits before targeting.',
      );
    }
    if (_has(message, 'idempotency_conflict')) {
      return const ConflictError(
        conflictCode: 'idempotency_conflict',
        debugMessage: 'The retry key was reused with a different payload.',
      );
    }
    if (_has(message, 'selection_policy_pending')) {
      // Retained for a pre-upgrade server only; the reviewed multi-negotiation
      // policy no longer emits this code.
      return const ConflictError(
        conflictCode: 'selection_policy_pending',
        debugMessage: 'This server has not enabled multiple negotiations yet.',
      );
    }
    if (_has(message, 'request_expired')) {
      return ValidationError(
        issues: const [
          ValidationIssue(
            field: 'request_id',
            code: 'request_expired',
            message: 'This request closed to new offers.',
          ),
        ],
        debugMessage: 'This request closed to new offers.',
      );
    }
    if (_has(message, 'purchase_seller_required')) {
      return const ConflictError(
        conflictCode: 'purchase_seller_required',
        debugMessage:
            'Only the buyer\u2019s chosen purchase seller can confirm.',
      );
    }
    if (_has(message, 'offer_not_selected')) {
      return const ConflictError(
        conflictCode: 'offer_not_selected',
        debugMessage: 'Accept this offer before choosing it for the purchase.',
      );
    }
    if (_has(message, 'sale_already_confirmed')) {
      return const ConflictError(
        conflictCode: 'sale_already_confirmed',
        debugMessage: 'This request already has a confirmed purchase.',
      );
    }
    if (_has(message, 'offer_exists')) {
      return const ConflictError(
        conflictCode: 'offer_exists',
        debugMessage: 'This seller already has an active offer on the request.',
      );
    }
    if (_has(message, 'offer_revision_conflict')) {
      return const ConflictError(
        conflictCode: 'offer_revision_conflict',
        debugMessage: 'The selected offer revision is no longer selectable.',
      );
    }
    if (_has(message, 'revision_conflict')) {
      return const ConflictError(
        conflictCode: 'revision_conflict',
        debugMessage: 'The record changed before this action.',
      );
    }
    for (final code in const [
      'request_not_open',
      'request_not_editable',
      'request_not_reopenable',
      'offer_not_open',
      'listing_not_editable',
      'conversation_not_eligible',
      'chat_foundation_missing',
      'meeting_not_open',
      'meeting_already_exists',
      'meeting_reschedule_pending',
      'meeting_not_accepted',
      'meeting_self_accept',
      'meeting_offer_not_selected',
      'meeting_cancelled',
    ]) {
      if (_has(message, code)) {
        return ConflictError(
          conflictCode: code,
          debugMessage: 'The server rejected this transition.',
        );
      }
    }
    if (_has(message, 'ambiguous_local_time')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'scheduleOccurrence',
            code: 'ambiguous_local_time',
            message:
                'This local time happens twice. Choose which occurrence applies.',
          ),
        ],
        debugMessage: 'The named zone repeats this local time.',
      );
    }
    if (_has(message, 'nonexistent_local_time')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'scheduleTime',
            code: 'nonexistent_local_time',
            message:
                'This local time does not exist in the chosen zone. Pick another time.',
          ),
        ],
        debugMessage: 'The named zone skips this local time.',
      );
    }
    if (_has(message, 'required_category_answers')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'categoryAnswers',
            code: ValidationCodes.requiredField,
            message:
                'Category questions have changed. Reload them and answer the required questions.',
          ),
        ],
      );
    }
    if (_has(message, 'invalid_field: category_answers')) {
      return const ValidationError(
        issues: [
          ValidationIssue(
            field: 'categoryAnswers',
            code: ValidationCodes.invalidValue,
            message:
                'A selected category choice is no longer available. Reload the questions and choose again.',
          ),
        ],
      );
    }
    if (_has(message, 'invalid_category')) {
      return _invalidField('categoryId');
    }
    if (_has(message, 'invalid_cursor')) {
      return _invalidField('cursor');
    }
    if (_has(message, 'invalid_field: ')) {
      final field = message
          .split('invalid_field: ')
          .last
          .split(RegExp(r'[\s"]'))
          .first;
      return _invalidField(field);
    }
    if (_has(message, 'invalid_request') ||
        _has(message, 'invalid_offer') ||
        _has(message, 'invalid_listing')) {
      return _invalidField('value');
    }
    if (_has(message, 'invalid_command') ||
        _has(message, 'invalid_operation') ||
        _has(message, 'invalid_scope')) {
      return _invalidField('operation');
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
      case '42501':
        return const PermissionDeniedError(
          action: 'marketplace',
          entityType: 'record',
        );
      case '404':
      case 'P0002':
        return const NotFoundError(entityType: 'record', entityId: 'requested');
      case '22023':
        return _invalidField('value');
      case '23514':
      case '23503':
        return const ValidationError(
          issues: [
            ValidationIssue(
              field: 'value',
              code: ValidationCodes.invalidValue,
              message:
                  'A marketplace value violates an allowed length or reference.',
            ),
          ],
          debugMessage:
              'A marketplace column check or reference rejected the value.',
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
          message: 'The server rejected this value.',
        ),
      ],
    );
  }

  static bool _has(String message, String needle) => message.contains(needle);
}
