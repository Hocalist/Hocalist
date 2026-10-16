/// Concrete chat transport over the official Supabase Flutter SDK.
///
/// RPC-only, restricted to the `hocalist` schema and the reviewed chat
/// functions. The captured access token is pinned on each request so a queued
/// call can never be sent with a replacement identity's token. Signed-out
/// calls return an `unauthorized` result before any HTTP request. There is no
/// service-role or API-key pathway.
library;

import 'dart:async';

import '../accounts/fresh_session_token.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_transport.dart';

class SupabaseChatTransport implements ChatTransport {
  SupabaseChatTransport(this._client);

  static const String schema = 'hocalist';
  static const Set<String> allowedFunctions = {
    'chat_inbox',
    'chat_conversation',
    'chat_messages',
    'chat_send',
    'chat_send_attachment',
    'chat_mark_read',
    'chat_set_muted',
    'chat_block',
    'chat_unblock',
    'chat_block_state',
    'chat_search',
    'chat_search_inbox',
  };

  final SupabaseClient _client;

  @override
  Future<ChatTransportResponse> callChatRpc(ChatRpcCall call) async {
    if (call.schema != schema) {
      throw UnsupportedError('Unsupported chat schema');
    }
    if (!allowedFunctions.contains(call.function)) {
      throw UnsupportedError('Unsupported chat function');
    }
    try {
      final token = await freshSessionToken(_client);
      if (token == null) return _unauthorized;
      final data = await _client
          .schema(schema)
          .rpc(call.function, params: call.params)
          .setHeader('Authorization', 'Bearer $token');
      return ChatTransportData(data);
    } on PostgrestException catch (error) {
      return _fromPostgrest(error);
    } on AuthRetryableFetchException {
      return _connectivity;
    } on AuthException {
      return _unauthorized;
    } on TimeoutException {
      return _connectivity;
    } on http.ClientException {
      return _connectivity;
    } on Exception {
      return const ChatTransportError(kind: ChatTransportErrorKind.server);
    }
  }

  ChatTransportError _fromPostgrest(PostgrestException error) {
    final code = error.code;
    final parsedCode = int.tryParse(code ?? '');
    final statusCode =
        parsedCode != null && parsedCode >= 100 && parsedCode <= 599
        ? parsedCode
        : null;
    final unauthorized =
        code == 'PGRST301' ||
        code == 'PGRST302' ||
        code == 'PGRST303' ||
        statusCode == 401;
    return ChatTransportError(
      kind: unauthorized
          ? ChatTransportErrorKind.unauthorized
          : ChatTransportErrorKind.server,
      code: code,
      message: error.message,
      statusCode: statusCode,
      retryable: statusCode != null && statusCode >= 500,
    );
  }

  static const ChatTransportResponse _unauthorized = ChatTransportError(
    kind: ChatTransportErrorKind.unauthorized,
  );

  static const ChatTransportResponse _connectivity = ChatTransportError(
    kind: ChatTransportErrorKind.connectivity,
    retryable: true,
  );
}
