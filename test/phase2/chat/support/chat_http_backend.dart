// Synthetic HTTP backend for the chat transport tests under the real SDK.
// No network and no credentials: synthetic URL/key and test tokens only.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../accounts/support/supabase_http_backend.dart';

class SyntheticChatBackend {
  final List<http.Request> requests = <http.Request>[];
  final Map<String, http.Response> rpcErrorOverrides = {};
  final Map<String, Map<String, Object?>> rpcResults = {};

  /// Hook invoked after recording a request and before routing it.
  Future<void> Function(http.Request request)? onRequest;

  final Map<String, String> _tokenToUser = {};
  int _tokenCounter = 0;

  MockClient client() => MockClient(_handle);

  List<http.Request> get rpcRequests => requests
      .where((request) => request.url.path.startsWith('/rest/v1/rpc/'))
      .toList(growable: false);

  String? userForToken(String token) => _tokenToUser[token];

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final hook = onRequest;
    if (hook != null) await hook(request);
    final http.Response routed;
    if (request.url.path.startsWith('/auth/v1/')) {
      routed = await _handleAuth(request);
    } else if (request.url.path.startsWith('/rest/v1/rpc/')) {
      final function = request.url.pathSegments.last;
      final error = rpcErrorOverrides[function];
      if (error != null) {
        routed = error;
      } else {
        routed = http.Response(
          jsonEncode(rpcResults[function] ?? const <String, Object?>{}),
          200,
        );
      }
    } else {
      routed = http.Response('{}', 404);
    }
    return http.Response.bytes(
      routed.bodyBytes,
      routed.statusCode,
      request: request,
      headers: routed.headers,
      reasonPhrase: routed.reasonPhrase,
    );
  }

  Future<http.Response> _handleAuth(http.Request request) async {
    if (request.url.path.endsWith('/logout')) {
      return http.Response('', 204);
    }
    if (request.url.path.endsWith('/token')) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final email = body['email'] as String? ?? '';
      final userId = email.startsWith('user-b')
          ? syntheticUserB
          : syntheticUserA;
      _tokenCounter += 1;
      final accessToken = 'access-$userId-$_tokenCounter';
      _tokenToUser[accessToken] = userId;
      return http.Response(
        jsonEncode(<String, Object?>{
          'access_token': accessToken,
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
    return http.Response('{}', 404);
  }
}
