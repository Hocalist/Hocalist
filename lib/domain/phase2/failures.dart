/// Typed results and failures returned by Phase 2 repository contracts.
///
/// Client-side checks are advisory. A [ValidationIssue] returned from a local
/// draft check does not replace server validation, row-level security or
/// authorization; repositories can always return a failure for data the
/// client accepted.
library;

/// One advisory field problem, safe to show next to a form field.
class ValidationIssue {
  const ValidationIssue({
    required this.field,
    required this.code,
    required this.message,
  });

  /// Logical field name, matching the editable model field where possible.
  final String field;

  /// Stable machine code from [ValidationCodes].
  final String code;

  /// Short, user-safe explanation.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ValidationIssue &&
      other.field == field &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, code, message);

  @override
  String toString() => 'ValidationIssue($field, $code, $message)';
}

/// Shared validation codes used by draft checks and server failures.
class ValidationCodes {
  const ValidationCodes._();

  static const String requiredField = 'required';
  static const String tooLong = 'too_long';
  static const String outOfRange = 'out_of_range';
  static const String invalidValue = 'invalid_value';
  static const String currencyMismatch = 'currency_mismatch';
}

/// Kinds of repository failure a caller may need to branch on.
enum RepositoryFailureKind {
  validation,
  conflict,
  notFound,
  permissionDenied,
  limitExceeded,
  network,
  malformedResponse,
  server,
}

/// Base type for typed repository failures.
sealed class RepositoryError {
  const RepositoryError({required this.kind, required this.debugMessage});

  final RepositoryFailureKind kind;

  /// Developer-facing description. It may contain identifiers but never
  /// credentials, PINs, payment data or message bodies.
  final String debugMessage;
}

/// The server rejected one or more field values (SEC-08).
final class ValidationError extends RepositoryError {
  const ValidationError({required this.issues, String? debugMessage})
    : super(
        kind: RepositoryFailureKind.validation,
        debugMessage: debugMessage ?? 'The submitted values were rejected.',
      );

  final List<ValidationIssue> issues;
}

/// A revision or acceptance check lost a race (SEC-13).
///
/// [conflictCode] is a stable server code such as `stale_revision`,
/// `offer_already_selected` or `reschedule_outdated`.
final class ConflictError extends RepositoryError {
  const ConflictError({
    required this.conflictCode,
    this.expectedRevision,
    this.actualRevision,
    String? debugMessage,
  }) : super(
         kind: RepositoryFailureKind.conflict,
         debugMessage: debugMessage ?? 'The record changed before this action.',
       );

  final String conflictCode;
  final int? expectedRevision;
  final int? actualRevision;
}

/// The requested record does not exist or is not visible to this caller.
final class NotFoundError extends RepositoryError {
  const NotFoundError({
    required this.entityType,
    required this.entityId,
    String? debugMessage,
  }) : super(
         kind: RepositoryFailureKind.notFound,
         debugMessage: debugMessage ?? 'The requested record was not found.',
       );

  final String entityType;
  final String entityId;
}

/// The authenticated identity is not allowed to perform this action (SEC-03).
///
/// A denial is a server decision. A hidden or disabled client control is not
/// an authorization test.
final class PermissionDeniedError extends RepositoryError {
  const PermissionDeniedError({
    required this.action,
    this.entityType,
    String? debugMessage,
  }) : super(
         kind: RepositoryFailureKind.permissionDenied,
         debugMessage: debugMessage ?? 'This action is not permitted.',
       );

  final String action;
  final String? entityType;
}

/// A server-owned plan or quota limit rejected the action (SEC-03, SEC-18).
///
/// Used for listing limits, weekly targeting capacity and similar counters.
/// The limit values come from server configuration; the client never derives
/// or raises them.
final class LimitExceededError extends RepositoryError {
  const LimitExceededError({
    required this.limitCode,
    this.limit,
    String? debugMessage,
  }) : super(
         kind: RepositoryFailureKind.limitExceeded,
         debugMessage: debugMessage ?? 'A server-managed limit was reached.',
       );

  /// Stable server code such as `listing_limit` or `weekly_target_limit`.
  final String limitCode;

  /// The configured limit when the server reports it.
  final int? limit;
}

/// The request did not reach the backend or the response was not usable.
final class NetworkError extends RepositoryError {
  const NetworkError({this.retryable = true, String? debugMessage})
    : super(
        kind: RepositoryFailureKind.network,
        debugMessage: debugMessage ?? 'The network request failed.',
      );

  /// Whether an unchanged retry with the same idempotency key is safe.
  final bool retryable;
}

/// The server responded, but the payload did not match the agreed contract.
///
/// [detail] is a safe field path or short reason such as
/// `memberships.role`; it never contains the response body, contacts or
/// other private payload values. This is distinguishable from [NetworkError]
/// so callers can decide between retrying and treating the response as
/// corrupt.
final class MalformedResponseError extends RepositoryError {
  const MalformedResponseError({required this.operation, required this.detail})
    : super(
        kind: RepositoryFailureKind.malformedResponse,
        debugMessage: 'The server response did not match the contract.',
      );

  final String operation;

  /// Safe, non-payload description of the mismatch.
  final String detail;
}

/// The server rejected the operation with an unrecognized error.
///
/// Used when no known contract code applies. The raw server message is
/// deliberately not propagated; callers should treat it as an unexpected
/// server failure rather than a validation result.
final class ServerError extends RepositoryError {
  const ServerError({required this.operation, this.statusCode})
    : super(
        kind: RepositoryFailureKind.server,
        debugMessage: 'The server rejected the operation.',
      );

  final String operation;
  final int? statusCode;
}

/// Outcome of one repository call.
sealed class RepositoryResult<T> {
  const RepositoryResult();

  bool get isSuccess => this is RepositorySuccess<T>;

  bool get isFailure => this is RepositoryFailureResult<T>;

  /// The value when this is a success, otherwise null.
  T? get valueOrNull => switch (this) {
    RepositorySuccess<T>(:final value) => value,
    RepositoryFailureResult<T>() => null,
  };

  /// The typed error when this is a failure, otherwise null.
  RepositoryError? get errorOrNull => switch (this) {
    RepositorySuccess<T>() => null,
    RepositoryFailureResult<T>(:final error) => error,
  };
}

/// A successful repository call.
final class RepositorySuccess<T> extends RepositoryResult<T> {
  const RepositorySuccess(this.value);

  final T value;

  @override
  String toString() => 'RepositorySuccess($value)';
}

/// A failed repository call with one typed error.
final class RepositoryFailureResult<T> extends RepositoryResult<T> {
  const RepositoryFailureResult(this.error);

  final RepositoryError error;

  @override
  String toString() => 'RepositoryFailureResult($error)';
}
