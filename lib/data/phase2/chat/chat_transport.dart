/// Minimal transport boundary for the chat data layer.
///
/// All chat access is RPC-only: there are deliberately no table selects, no
/// query builder and no credential option. The concrete implementation uses
/// the caller's authenticated Supabase session; there is no service-role or
/// API-key pathway.
library;

/// One explicit RPC call with an exact schema, function and parameter map.
class ChatRpcCall {
  ChatRpcCall({
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
      'ChatRpcCall($schema.$function, params: ${params.length})';
}

/// Outcome of one chat transport call.
sealed class ChatTransportResponse {
  const ChatTransportResponse();
}

/// The transport received a usable response body.
final class ChatTransportData extends ChatTransportResponse {
  const ChatTransportData(this.data);

  final Object? data;

  @override
  String toString() => 'ChatTransportData(${data.runtimeType})';
}

/// The transport failed before a usable response existed.
final class ChatTransportError extends ChatTransportResponse {
  const ChatTransportError({
    required this.kind,
    this.code,
    this.message,
    this.statusCode,
    this.retryable = false,
  });

  final ChatTransportErrorKind kind;

  /// Server code such as a SQLSTATE. Used only for mapping.
  final String? code;

  /// Raw server message. Used only for mapping, never propagated.
  final String? message;

  final int? statusCode;

  /// Whether an unchanged retry with the same key is safe.
  final bool retryable;

  @override
  String toString() =>
      'ChatTransportError(${kind.name}, code: ${code ?? 'none'})';
}

enum ChatTransportErrorKind { connectivity, unauthorized, server }

/// Injected chat transport. Implementations must use the caller's
/// authenticated session and must not accept service-role credentials.
abstract interface class ChatTransport {
  Future<ChatTransportResponse> callChatRpc(ChatRpcCall call);
}

String _requireIdentifier(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}
