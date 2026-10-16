// SDK-level chat transport tests over a synthetic HTTP backend.
//
// No network, no credentials and no live project: the SDK client uses a
// MockClient and synthetic publishable keys.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';
import 'package:hocalist/data/phase2/chat/supabase_chat_transport.dart';
import 'package:http/http.dart' as http;

import '../accounts/support/supabase_http_backend.dart';
import 'support/chat_http_backend.dart';

void main() {
  late SyntheticChatBackend backend;

  setUp(() {
    backend = SyntheticChatBackend();
  });

  test('signed-out calls return unauthorized without a request', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    final transport = SupabaseChatTransport(client);

    final response = await transport.callChatRpc(
      ChatRpcCall(
        schema: 'hocalist',
        function: 'chat_inbox',
        params: const {'p_page_size': 20},
      ),
    );

    expect(response, isA<ChatTransportError>());
    expect(
      (response as ChatTransportError).kind,
      ChatTransportErrorKind.unauthorized,
    );
    expect(backend.rpcRequests, isEmpty);
  });

  test('send posts the exact pinned wire shape', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    final auth = await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final token = auth.session!.accessToken;
    backend.rpcResults['chat_send'] = <String, Object?>{'id': 'm1'};

    final transport = SupabaseChatTransport(client);
    final response = await transport.callChatRpc(
      ChatRpcCall(
        schema: 'hocalist',
        function: 'chat_send',
        params: const {
          'p_conversation': '50000000-0000-4000-8000-000000000001',
          'p_key': 'stable-key',
          'p_text': 'Hello',
        },
      ),
    );

    expect(response, isA<ChatTransportData>());
    expect((response as ChatTransportData).data, {'id': 'm1'});
    final request = backend.rpcRequests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/rpc/chat_send');
    expect(request.headers['apikey'], syntheticPublishableKey);
    expect(request.headers['Authorization'], 'Bearer $token');
    // The SDK sends Content-Profile (not Accept-Profile) for RPC POSTs.
    expect(request.headers['Content-Profile'], 'hocalist');
    expect(jsonDecode(request.body), {
      'p_conversation': '50000000-0000-4000-8000-000000000001',
      'p_key': 'stable-key',
      'p_text': 'Hello',
    });
  });

  test('unknown schema and function are rejected locally', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final transport = SupabaseChatTransport(client);

    await expectLater(
      transport.callChatRpc(
        ChatRpcCall(schema: 'public', function: 'chat_inbox', params: const {}),
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      transport.callChatRpc(
        ChatRpcCall(
          schema: 'hocalist',
          function: 'chat_delete_everything',
          params: const {},
        ),
      ),
      throwsUnsupportedError,
    );
    expect(backend.rpcRequests, isEmpty);
  });

  test('maps PostgREST SQLSTATE, status and server errors', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final transport = SupabaseChatTransport(client);

    backend.rpcErrorOverrides['chat_send'] = http.Response(
      jsonEncode({'code': '22023', 'message': 'invalid_message'}),
      400,
    );
    var response = await transport.callChatRpc(
      ChatRpcCall(schema: 'hocalist', function: 'chat_send', params: const {}),
    );
    expect((response as ChatTransportError).code, '22023');
    expect(
      response.statusCode,
      isNull,
      reason: 'SQLSTATE is not an HTTP status',
    );

    backend.rpcErrorOverrides['chat_inbox'] = http.Response(
      jsonEncode({'code': 'PGRST301', 'message': 'JWT expired'}),
      401,
    );
    response = await transport.callChatRpc(
      ChatRpcCall(schema: 'hocalist', function: 'chat_inbox', params: const {}),
    );
    expect(
      (response as ChatTransportError).kind,
      ChatTransportErrorKind.unauthorized,
    );

    backend.rpcErrorOverrides['chat_messages'] = http.Response(
      jsonEncode({'message': 'boom'}),
      500,
    );
    response = await transport.callChatRpc(
      ChatRpcCall(
        schema: 'hocalist',
        function: 'chat_messages',
        params: const {},
      ),
    );
    expect(
      (response as ChatTransportError).kind,
      ChatTransportErrorKind.server,
    );
    expect(response.statusCode, 500);
    expect(response.retryable, isTrue);
  });

  test('a queued request keeps the initiating identity token', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    final first = await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final firstToken = first.session!.accessToken;
    final seen = <String?>[];
    backend.onRequest = (request) async {
      if (request.url.path.startsWith('/rest/v1/rpc/')) {
        seen.add(request.headers['Authorization']);
        await client.auth.signInWithPassword(
          email: 'user-b@example.invalid',
          password: 'synthetic',
        );
      }
    };

    final transport = SupabaseChatTransport(client);
    await transport.callChatRpc(
      ChatRpcCall(schema: 'hocalist', function: 'chat_inbox', params: const {}),
    );

    expect(seen.single, 'Bearer $firstToken');
    expect(backend.userForToken(firstToken), syntheticUserA);
    expect(client.auth.currentUser?.id, syntheticUserB);
  });
}
