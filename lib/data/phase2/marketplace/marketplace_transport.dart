/// Minimal transport boundary for the marketplace data layer.
///
/// All marketplace access is RPC-only: there are deliberately no table
/// selects, no query builder and no credential option. The concrete
/// implementation uses the caller's authenticated Supabase session; there is
/// no service-role or API-key pathway.
library;

/// One explicit RPC call with an exact schema, function and parameter map.
class MarketplaceRpcCall {
  MarketplaceRpcCall({
    required String schema,
    required String function,
    required Map<String, Object?> params,
  }) : schema = _requireIdentifier(schema, 'schema'),
       function = _requireIdentifier(function, 'function'),
       params = Map<String, Object?>.unmodifiable(params);

  final String schema;
  final String function;
  final Map<String, Object?> params;

  @override
  String toString() =>
      'MarketplaceRpcCall($schema.$function, params: ${params.length})';
}

/// Outcome of one marketplace transport call.
sealed class MarketplaceTransportResponse {
  const MarketplaceTransportResponse();
}

/// The transport received a usable response body.
final class MarketplaceTransportData extends MarketplaceTransportResponse {
  const MarketplaceTransportData(this.data);

  final Object? data;

  @override
  String toString() => 'MarketplaceTransportData(${data.runtimeType})';
}

/// The transport failed before a usable response existed.
final class MarketplaceTransportError extends MarketplaceTransportResponse {
  const MarketplaceTransportError({
    required this.kind,
    this.code,
    this.message,
    this.statusCode,
    this.retryable = false,
  });

  final MarketplaceTransportErrorKind kind;

  /// Server code such as a SQLSTATE. Used only for mapping.
  final String? code;

  /// Raw server message. Used only for mapping, never propagated.
  final String? message;

  final int? statusCode;

  /// Whether an unchanged retry with the same key is safe.
  final bool retryable;

  @override
  String toString() =>
      'MarketplaceTransportError(${kind.name}, code: ${code ?? 'none'})';
}

enum MarketplaceTransportErrorKind { connectivity, unauthorized, server }

/// Injected marketplace transport. Implementations must use the caller's
/// authenticated session and must not accept service-role credentials.
abstract interface class MarketplaceTransport {
  Future<MarketplaceTransportResponse> callMarketplaceRpc(
    MarketplaceRpcCall call,
  );
}

String _requireIdentifier(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}
