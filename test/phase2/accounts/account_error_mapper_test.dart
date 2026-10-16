import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_error_mapper.dart';
import 'package:hocalist/data/phase2/accounts/account_transport.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  const mapper = AccountErrorMapper();

  AccountTransportError server(String? message, {String? code}) {
    return AccountTransportError(
      kind: AccountTransportErrorKind.server,
      message: message,
      code: code,
    );
  }

  group('transport failure kinds', () {
    test('connectivity maps to a retryable network error', () {
      final error = mapper.map(
        const AccountTransportError(
          kind: AccountTransportErrorKind.connectivity,
          retryable: true,
        ),
        operation: 'contact.update',
      );

      expect(error.kind, RepositoryFailureKind.network);
      expect((error as NetworkError).retryable, isTrue);
    });

    test('unauthorized maps to a permission failure', () {
      final error = mapper.map(
        const AccountTransportError(
          kind: AccountTransportErrorKind.unauthorized,
        ),
        operation: 'memberships.select',
      );

      expect(error.kind, RepositoryFailureKind.permissionDenied);
      expect((error as PermissionDeniedError).action, 'authenticate');
    });
  });

  group('known SQL messages', () {
    test('revision, idempotency and membership conflicts', () {
      final revision = mapper.map(
        server('revision_conflict', code: 'P0001'),
        operation: 'profile.update',
      );
      expect(revision.kind, RepositoryFailureKind.conflict);
      expect((revision as ConflictError).conflictCode, 'revision_conflict');

      final idempotency = mapper.map(
        server('idempotency_conflict', code: 'P0001'),
        operation: 'contact.update',
      );
      expect(
        (idempotency as ConflictError).conflictCode,
        'idempotency_conflict',
      );

      final membership = mapper.map(
        server('membership_exists', code: 'P0001'),
        operation: 'onboard',
      );
      expect((membership as ConflictError).conflictCode, 'membership_exists');
    });

    test('access and restriction errors stay distinguishable', () {
      final cases = <String, String>{
        'authentication_required': 'authenticate',
        'onboarding_seed_required': 'onboarding_seed_required',
        'account_restricted': 'account_restricted',
        'profile_access_denied': 'profile_access_denied',
        'contact_access_denied': 'contact_access_denied',
      };
      for (final entry in cases.entries) {
        final error = mapper.map(
          server(entry.key, code: '42501'),
          operation: 'account_command',
        );
        expect(error.kind, RepositoryFailureKind.permissionDenied);
        expect((error as PermissionDeniedError).action, entry.value);
      }
    });

    test('invalid input maps to validation issues', () {
      final cases = <String, String>{
        'invalid_display_name': 'display_name',
        'invalid_revision': 'expected_revision',
        'invalid_profile_id': 'profile_id',
        'invalid_radius': 'service_radius_miles',
        'invalid_role': 'role',
        'invalid_operation': 'operation',
        'unknown_field': 'request',
        'invalid_field_type': 'request',
        'invalid_command': 'request',
      };
      for (final entry in cases.entries) {
        final error = mapper.map(
          server(entry.key, code: '22023'),
          operation: 'account_command',
        );
        expect(error.kind, RepositoryFailureKind.validation);
        final validation = error as ValidationError;
        expect(validation.issues.single.field, entry.value);
      }

      final sellerFields = mapper.map(
        server('seller_fields_on_buyer', code: '22023'),
        operation: 'profile.update',
      );
      expect(sellerFields.kind, RepositoryFailureKind.validation);
      expect(
        (sellerFields as ValidationError).issues.single.field,
        'service_radius_miles',
      );
    });
  });

  group('unknown and fallback errors', () {
    test('unknown server messages never leak raw text', () {
      const sentinel = 'SENTINEL-RAW-SERVER-MESSAGE';
      final error = mapper.map(
        server(sentinel, code: 'XX999'),
        operation: 'profile.update',
      );

      expect(error.kind, RepositoryFailureKind.server);
      expect(error.debugMessage.contains(sentinel), isFalse);
      expect(error.toString().contains(sentinel), isFalse);
      expect((error as ServerError).operation, 'profile.update');
    });

    test('unknown P0001 raises map safely', () {
      final error = mapper.map(
        server('some_new_raise', code: 'P0001'),
        operation: 'onboard',
      );
      expect(error.kind, RepositoryFailureKind.server);
    });

    test('SQLSTATE fallbacks map to typed failures', () {
      final denied = mapper.map(server(null, code: '42501'), operation: 'x');
      expect(denied.kind, RepositoryFailureKind.permissionDenied);

      final invalid = mapper.map(server(null, code: '22023'), operation: 'x');
      expect(invalid.kind, RepositoryFailureKind.validation);

      final check = mapper.map(server(null, code: '23514'), operation: 'x');
      expect(check.kind, RepositoryFailureKind.validation);
      expect(
        (check as ValidationError).issues.single.code,
        ValidationCodes.outOfRange,
      );

      final duplicate = mapper.map(server(null, code: '23505'), operation: 'x');
      expect(duplicate.kind, RepositoryFailureKind.conflict);

      final reference = mapper.map(server(null, code: '23503'), operation: 'x');
      expect(reference.kind, RepositoryFailureKind.validation);
    });
  });
}
