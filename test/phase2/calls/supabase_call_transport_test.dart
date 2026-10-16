// SDK-level transport proof for the call lifecycle status RPC.
//
// This test belongs with the integration patch that adds `call_status` to the
// shared marketplace transport allowlist. It uses the real Supabase client
// over a synthetic in-memory HTTP backend: no network, no credentials and no
// live project. It proves the RPC path, schema, parameters, pinned identity and
// safe error mapping rather than only injecting a fake CallService.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/calls/call_gateway.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/marketplace/supabase_marketplace_transport.dart';
import 'package:hocalist/domain/phase2/communication_completion.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../accounts/support/supabase_http_backend.dart';

const callId = '30000000-0000-4000-8000-000000000001';

Map<String, Object?> callStatusJson({
  String state = 'ringing',
  bool enabled = true,
}) => <String, Object?>{
  'call': <String, Object?>{
    'id': callId,
    'conversation_id': '50000000-0000-4000-8000-000000000001',
    'caller_id': syntheticUserA,
    'callee_id': syntheticUserB,
    'state': state,
    'created_at': '2026-09-26T12:00:00+00:00',
    'expires_at': '2026-09-26T12:00:45+00:00',
    'terminal': false,
  },
  'signals': <Object?>[
    <String, Object?>{
      'seq': 3,
      'kind': 'offer',
      'payload': <String, Object?>{'sdp': 'synthetic'},
    },
  ],
  'server_now': '2026-09-26T12:00:10+00:00',
  'enabled': enabled,
  'settings_revision': 2,
};

class _CallBackend {
  final List<http.Request> requests = <http.Request>[];
  Map<String, Object?> result = callStatusJson();
  http.Response? errorOverride;
  Future<void> Function(http.Request request)? onRequest;
  int _tokenCounter = 0;

  MockClient client() => MockClient(_handle);

  List<http.Request> get rpcRequests => requests
      .where((request) => request.url.path.startsWith('/rest/v1/rpc/'))
      .toList(growable: false);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final hook = onRequest;
    if (hook != null) await hook(request);
    final routed = await _route(request);
    // PostgREST reads `response.request!`; every mocked response must carry it.
    return http.Response.bytes(
      routed.bodyBytes,
      routed.statusCode,
      request: request,
      headers: routed.headers,
      reasonPhrase: routed.reasonPhrase,
    );
  }

  Future<http.Response> _route(http.Request request) async {
    if (request.url.path.startsWith('/auth/v1/')) {
      _tokenCounter += 1;
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final email = body['email'] as String? ?? '';
      final userId = email.startsWith('user-b')
          ? syntheticUserB
          : syntheticUserA;
      return http.Response(
        jsonEncode(<String, Object?>{
          'access_token': 'access-$userId-$_tokenCounter',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-$userId-$_tokenCounter',
          'user': <String, Object?>{
            'id': userId,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': email,
            'app_metadata': <String, Object?>{
              'provider': 'email',
              'providers': <String>['email'],
            },
            'user_metadata': <String, Object?>{},
            'created_at': '2026-05-01T00:00:00Z',
          },
        }),
        200,
      );
    }
    if (request.url.path.startsWith('/rest/v1/rpc/')) {
      final error = errorOverride;
      if (error != null) return error;
      return http.Response(jsonEncode(result), 200);
    }
    return http.Response('{}', 404);
  }
}

void main() {
  late _CallBackend backend;

  setUp(() {
    backend = _CallBackend();
  });

  test('the reviewed transport allowlist includes call_status', () {
    expect(
      SupabaseMarketplaceTransport.allowedFunctions,
      contains('call_status'),
    );
  });

  test('status posts the exact pinned wire shape and decodes the snapshot', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    final auth = await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final token = auth.session!.accessToken;
    final gateway = CallGateway(client);

    final snapshot = await gateway.status(callId, cursor: 3);

    expect(snapshot.call.state, CallLifecycleState.ringing);
    expect(snapshot.call.isTerminal, isFalse);
    expect(snapshot.call.enabled, isTrue);
    expect(snapshot.call.settingsRevision, 2);
    expect(snapshot.call.expiresAt.isAfter(snapshot.call.serverNow), isTrue);
    expect(snapshot.signals.single.kind, 'offer');

    final request = backend.rpcRequests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/rpc/call_status');
    expect(request.headers['apikey'], syntheticPublishableKey);
    expect(request.headers['Authorization'], 'Bearer $token');
    expect(request.headers['Content-Profile'], 'hocalist');
    expect(jsonDecode(request.body), {'p_call_id': callId, 'p_cursor': 3});
  });

  test('a replacement identity mid-request discards the snapshot', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final gateway = CallGateway(client);
    backend.onRequest = (request) async {
      if (request.url.path.startsWith('/rest/v1/rpc/')) {
        await client.auth.signInWithPassword(
          email: 'user-b@example.invalid',
          password: 'synthetic',
        );
      }
    };

    await expectLater(
      gateway.status(callId),
      throwsA(
        isA<CallGatewayException>().having(
          (error) => error.code,
          'code',
          'session_changed',
        ),
      ),
    );
  });

  test('server denials map to stable safe codes', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final gateway = CallGateway(client);

    Future<String> codeFor(http.Response response) async {
      backend.errorOverride = response;
      try {
        await gateway.status(callId);
        fail('expected a failure');
      } on CallGatewayException catch (error) {
        return error.code;
      }
    }

    expect(
      await codeFor(
        http.Response(jsonEncode({'code': '42501', 'message': 'call_access_denied'}), 403),
      ),
      'call_access_denied',
    );
    expect(
      await codeFor(
        http.Response(jsonEncode({'code': 'P0002', 'message': 'call_not_found'}), 404),
      ),
      'call_not_found',
    );
    expect(
      await codeFor(http.Response(jsonEncode({'message': 'boom'}), 500)),
      'call_unavailable',
    );
  });

  test('a signed-out transport call stays unauthorized without a request', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    final transport = SupabaseMarketplaceTransport(client);

    final response = await transport.callMarketplaceRpc(
      MarketplaceRpcCall(
        schema: 'hocalist',
        function: 'call_status',
        params: const {'p_call_id': callId, 'p_cursor': 0},
      ),
    );

    expect(response, isA<MarketplaceTransportError>());
    expect(
      (response as MarketplaceTransportError).kind,
      MarketplaceTransportErrorKind.unauthorized,
    );
    expect(backend.rpcRequests, isEmpty);
  });

  test('the transport still rejects functions outside the allowlist', () async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: 'user-a@example.invalid',
      password: 'synthetic',
    );
    final transport = SupabaseMarketplaceTransport(client);
    await expectLater(
      transport.callMarketplaceRpc(
        MarketplaceRpcCall(
          schema: 'hocalist',
          function: 'call_delete_everything',
          params: const {},
        ),
      ),
      throwsUnsupportedError,
    );
    expect(backend.rpcRequests, isEmpty);
  });
}
