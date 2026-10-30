/// Synthetic HTTP backend under the real Supabase SDK.
///
/// Routes the SDK's auth and PostgREST calls to deterministic in-memory
/// responses. No network, no credentials: the URL and publishable key are
/// synthetic sentinels and the tokens are test strings.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String syntheticSupabaseUrl = 'https://synthetic.supabase.co';
const String syntheticPublishableKey = 'sb_publishable_synthetic';
const String syntheticUserA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const String syntheticUserB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

/// Builds the SDK client over a fake HTTP client.
SupabaseClient buildSyntheticSupabaseClient(
  http.Client httpClient, {
  Duration? requestTimeout,
}) {
  return SupabaseClient(
    syntheticSupabaseUrl,
    syntheticPublishableKey,
    httpClient: httpClient,
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: _MemoryAsyncStorage(),
    ),
    postgrestOptions: PostgrestClientOptions(
      schema: 'hocalist',
      retryEnabled: false,
      requestTimeout: requestTimeout,
    ),
  );
}

/// Minimal in-memory PKCE storage for the synthetic client.
class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

class SyntheticAccountBackend {
  bool emailConfirmed = true;
  final List<http.Request> requests = <http.Request>[];
  final Map<String, List<Map<String, Object?>>> tableRows = {};
  final Map<String, http.Response> tableErrorOverrides = {};
  final Map<String, http.Response> commandErrorOverrides = {};
  final Map<String, Map<String, Object?>> commandResults = {
    'onboard': {
      'profile_id': '11111111-1111-1111-1111-111111111111',
      'role': 'buyer',
      'revision': 1,
    },
    'profile.update': {
      'profile_id': '11111111-1111-1111-1111-111111111111',
      'revision': 2,
    },
    'contact.update': {'revision': 2},
  };

  /// Hook invoked after recording a request and before routing it.
  Future<void> Function(http.Request request)? onRequest;

  final Map<String, String> _tokenToUser = {};
  final Map<String, String> _refreshTokenToUser = {};
  int _tokenCounter = 0;

  MockClient client() => MockClient(_handle);

  List<http.Request> get restRequests => requests
      .where((request) => request.url.path.startsWith('/rest/v1/'))
      .toList(growable: false);

  List<Map<String, Object?>> get commandInputs => restRequests
      .where((request) => request.url.path.startsWith('/rest/v1/rpc/'))
      .map((request) => (jsonDecode(request.body) as Map<String, Object?>))
      .toList(growable: false);

  /// The user id associated with an issued access token.
  String? userForToken(String token) => _tokenToUser[token];

  /// Issues a deterministic session for a synthetic user so tests can build
  /// provider callback URLs (for example a recovery link fragment).
  Map<String, Object?> issueSession(String userId) => _issueSession(userId);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final hook = onRequest;
    if (hook != null) await hook(request);
    final path = request.url.path;
    final http.Response routed;
    if (path.startsWith('/auth/v1/')) {
      routed = await _handleAuth(request);
    } else if (path.startsWith('/rest/v1/rpc/')) {
      routed = _handleRpc(request);
    } else if (path.startsWith('/rest/v1/')) {
      routed = _handleRest(request);
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
    if (request.url.path.endsWith('/recover')) {
      return http.Response('{}', 200);
    }
    if (request.url.path.endsWith('/user')) {
      final auth =
          request.headers['Authorization'] ??
          request.headers['authorization'] ??
          '';
      final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
      final userId = _tokenToUser[token];
      if (userId == null) {
        return http.Response(
          jsonEncode({
            'error_code': 'invalid_token',
            'message': 'Invalid token',
          }),
          401,
        );
      }
      if (request.method == 'GET') {
        return http.Response(jsonEncode(_userJson(userId)), 200);
      }
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final user = _userJson(userId);
        if (body['email'] is String) {
          user['new_email'] = body['email'];
          user['email_change_sent_at'] = '2026-05-01T00:00:00Z';
        }
        return http.Response(jsonEncode(user), 200);
      }
    }
    if (request.url.path.endsWith('/token')) {
      final grant = request.url.queryParameters['grant_type'];
      if (grant == 'refresh_token') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final refreshToken = body['refresh_token'] as String? ?? '';
        final userId = _refreshTokenToUser[refreshToken];
        if (userId == null) {
          return http.Response(
            jsonEncode({'message': 'Invalid refresh token'}),
            400,
          );
        }
        return http.Response(jsonEncode(_issueSession(userId)), 200);
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (body['password'] == 'wrong-password') {
        return http.Response(
          jsonEncode({
            'error_code': 'invalid_credentials',
            'message': 'Invalid login credentials',
          }),
          400,
        );
      }
      final email = body['email'] as String? ?? '';
      final userId =
          email.startsWith('user-a') || email.startsWith(syntheticUserA)
          ? syntheticUserA
          : syntheticUserB;
      return http.Response(jsonEncode(_issueSession(userId)), 200);
    }
    return http.Response('{}', 404);
  }

  Map<String, Object?> _userJson(String userId) => <String, Object?>{
    'id': userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': '$userId@example.com',
    if (emailConfirmed) 'email_confirmed_at': '2026-05-01T00:00:00Z',
    'app_metadata': <String, Object?>{
      'provider': 'email',
      'providers': <String>['email'],
    },
    'user_metadata': <String, Object?>{},
    'created_at': '2026-05-01T00:00:00Z',
  };

  Map<String, Object?> _issueSession(String userId) {
    _tokenCounter += 1;
    final accessToken = 'access-$userId-$_tokenCounter';
    final refreshToken = 'refresh-$userId-$_tokenCounter';
    _tokenToUser[accessToken] = userId;
    _refreshTokenToUser[refreshToken] = userId;
    return <String, Object?>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': refreshToken,
      'user': _userJson(userId),
    };
  }

  http.Response _handleRest(http.Request request) {
    final table = request.url.pathSegments.length > 2
        ? request.url.pathSegments[2]
        : '';
    final error = tableErrorOverrides[table];
    if (error != null) return error;
    return http.Response(jsonEncode(tableRows[table] ?? const []), 200);
  }

  http.Response _handleRpc(http.Request request) {
    final decoded = request.body.isEmpty ? null : jsonDecode(request.body);
    final body = decoded == null
        ? const <String, Object?>{}
        : decoded as Map<String, Object?>;
    final operation = body['p_operation'] as String? ?? '';
    final error = commandErrorOverrides[operation];
    if (error != null) return error;
    return http.Response(
      jsonEncode(commandResults[operation] ?? const <String, Object?>{}),
      200,
    );
  }
}
