/// Minimal transport boundary for the account data layer.
///
/// The adapter uses this interface to select the three reviewed account
/// tables and to call `hocalist.account_command`. There is deliberately no
/// generic networking framework, no query builder and no credential option:
/// the real implementation will use the caller's authenticated session
/// (see the account adapter handoff document), and there is no service-role
/// or API-key parameter anywhere in this boundary.
library;

/// One equality/is-null filter for a table select.
class AccountColumnFilter {
  const AccountColumnFilter.equals(this.column, this.value) : isNull = false;

  const AccountColumnFilter.isNull(this.column) : value = null, isNull = true;

  final String column;
  final Object? value;
  final bool isNull;

  @override
  String toString() =>
      'AccountColumnFilter($column ${isNull ? 'is null' : '= <value>'})';
}

/// An explicit schema/table select with columns, filters and an ordering.
///
/// [columns] is required so a transport can never fall back to `select *`
/// and accidentally request private or unsupported fields.
class AccountTableQuery {
  AccountTableQuery({
    required String schema,
    required String table,
    required List<String> columns,
    List<AccountColumnFilter> filters = const [],
    List<String> orderBy = const [],
  }) : schema = _requireIdentifier(schema, 'schema'),
       table = _requireIdentifier(table, 'table'),
       columns = _requireIdentifiers(columns, 'columns'),
       filters = List<AccountColumnFilter>.unmodifiable(filters),
       orderBy = _requireIdentifiers(orderBy, 'orderBy');

  final String schema;
  final String table;
  final List<String> columns;
  final List<AccountColumnFilter> filters;
  final List<String> orderBy;

  @override
  String toString() =>
      'AccountTableQuery($schema.$table, columns: ${columns.length}, '
      'filters: ${filters.length})';
}

/// Outcome of one transport call.
sealed class AccountTransportResponse {
  const AccountTransportResponse();
}

/// The transport received a response. [data] is a `List<Map<String, Object?>>`
/// for table selects and a `Map<String, Object?>` for the RPC.
final class AccountTransportData extends AccountTransportResponse {
  const AccountTransportData(this.data);

  final Object? data;

  @override
  String toString() => 'AccountTransportData(${data.runtimeType})';
}

/// The transport failed before a usable response existed.
final class AccountTransportError extends AccountTransportResponse {
  const AccountTransportError({
    required this.kind,
    this.code,
    this.message,
    this.statusCode,
    this.retryable = false,
  });

  final AccountTransportErrorKind kind;

  /// Server error code such as a SQLSTATE. Used only for mapping.
  final String? code;

  /// Raw server message. Used only for mapping and never propagated to a
  /// typed repository error.
  final String? message;

  final int? statusCode;

  /// Whether an unchanged retry with the same idempotency key is safe.
  final bool retryable;

  @override
  String toString() =>
      'AccountTransportError(${kind.name}, code: ${code ?? 'none'})';
}

enum AccountTransportErrorKind {
  /// The request never reached the backend (offline, timeout, DNS).
  connectivity,

  /// The session is missing, expired or rejected.
  unauthorized,

  /// The backend responded with an error status or database error.
  server,
}

/// Injected account transport. Implementations must use the caller's
/// authenticated session and must not accept service-role credentials.
abstract interface class AccountTransport {
  /// Selects rows from one explicit schema/table with filters.
  Future<AccountTransportResponse> selectRows(AccountTableQuery query);

  /// Calls the account RPC with the reviewed parameter shape.
  ///
  /// [schema] and [function] are explicit identifiers so the adapter never
  /// guesses the RPC location.
  Future<AccountTransportResponse> callAccountCommand({
    required String schema,
    required String function,
    required String operation,
    required String key,
    required Map<String, Object?> input,
  });
}

String _requireIdentifier(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}

List<String> _requireIdentifiers(List<String> values, String name) {
  final validated = <String>[];
  for (final value in values) {
    validated.add(_requireIdentifier(value, name));
  }
  return List<String>.unmodifiable(validated);
}
