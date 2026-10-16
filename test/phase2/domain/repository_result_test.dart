import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  group('RepositoryResult', () {
    test('carries a value on success and supports pattern matching', () {
      const RepositoryResult<int> result = RepositorySuccess<int>(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.errorOrNull, isNull);

      final label = switch (result) {
        RepositorySuccess<int>(:final value) => 'value:$value',
        RepositoryFailureResult<int>(:final error) => 'error:${error.kind}',
      };
      expect(label, 'value:42');
    });

    test('carries a typed error on failure', () {
      final result = RepositoryFailureResult<int>(
        ValidationError(
          issues: const [
            ValidationIssue(
              field: 'title',
              code: ValidationCodes.requiredField,
              message: 'Add a clear request title.',
            ),
          ],
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, isA<ValidationError>());
      expect(
        (result.errorOrNull! as ValidationError).issues.single.field,
        'title',
      );
    });
  });

  group('Failure types', () {
    test('validation failure exposes field issues', () {
      const error = ValidationError(
        issues: [
          ValidationIssue(
            field: 'price',
            code: ValidationCodes.invalidValue,
            message: 'Enter an offer price greater than zero.',
          ),
        ],
      );

      expect(error.kind, RepositoryFailureKind.validation);
      expect(error.issues.single.code, ValidationCodes.invalidValue);
    });

    test('conflict failure exposes the expected and actual revisions', () {
      const error = ConflictError(
        conflictCode: 'stale_revision',
        expectedRevision: 2,
        actualRevision: 3,
      );

      expect(error.kind, RepositoryFailureKind.conflict);
      expect(error.conflictCode, 'stale_revision');
      expect(error.expectedRevision, 2);
      expect(error.actualRevision, 3);
    });

    test('not-found, permission and network failures stay distinct', () {
      const notFound = NotFoundError(
        entityType: 'offer',
        entityId: 'offer-404',
      );
      const denied = PermissionDeniedError(
        action: 'select_offer',
        entityType: 'offer',
      );
      const network = NetworkError(retryable: true);

      expect(notFound.kind, RepositoryFailureKind.notFound);
      expect(denied.kind, RepositoryFailureKind.permissionDenied);
      expect(network.kind, RepositoryFailureKind.network);
      expect(network.retryable, isTrue);
      expect(notFound.debugMessage, isNotEmpty);
    });

    test('limit failures carry the server limit code', () {
      const error = LimitExceededError(limitCode: 'listing_limit', limit: 3);

      expect(error.kind, RepositoryFailureKind.limitExceeded);
      expect(error.limitCode, 'listing_limit');
      expect(error.limit, 3);
      expect(error.debugMessage, isNotEmpty);
    });

    test('malformed responses and server errors stay distinguishable', () {
      const malformed = MalformedResponseError(
        operation: 'memberships.select',
        detail: 'memberships.role',
      );
      const server = ServerError(operation: 'account_command', statusCode: 500);

      expect(malformed.kind, RepositoryFailureKind.malformedResponse);
      expect(malformed.detail, 'memberships.role');
      expect(server.kind, RepositoryFailureKind.server);
      expect(server.statusCode, 500);
    });
  });

  group('Pagination values', () {
    test('PageQuery bounds the limit and cursor', () {
      expect(PageQuery.standard.limit, 50);
      expect(PageQuery(limit: 10, cursor: 'cursor-1').limit, 10);
      expect(() => PageQuery(limit: 0), throwsArgumentError);
      expect(() => PageQuery(limit: 201), throwsArgumentError);
      expect(() => PageQuery(cursor: ' '), throwsArgumentError);
    });

    test('PageSlice is unmodifiable and reports more pages', () {
      final slice = PageSlice<int>(items: [1, 2], nextCursor: 'next');

      expect(slice.items, [1, 2]);
      expect(slice.hasMore, isTrue);
      expect(() => slice.items.add(3), throwsUnsupportedError);
      expect(PageSlice<int>(items: const [1]).hasMore, isFalse);
    });
  });

  group('MediaReference', () {
    test('keeps upload metadata without a public URL', () {
      final media = MediaReference(
        id: 'media-1',
        kind: MediaKind.image,
        fileName: 'offer-photo.jpg',
        contentType: 'image/jpeg',
        byteSize: 1024,
      );

      expect(media.isImage, isTrue);
      expect(media.fileName, 'offer-photo.jpg');
      expect(media.toString().contains('http'), isFalse);
    });

    test('rejects blank ids and negative sizes', () {
      expect(
        () => MediaReference(id: ' ', kind: MediaKind.image, fileName: 'a.png'),
        throwsArgumentError,
      );
      expect(
        () => MediaReference(
          id: 'media-1',
          kind: MediaKind.image,
          fileName: 'a.png',
          byteSize: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
