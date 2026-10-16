import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_adapter.dart';
import 'package:hocalist/data/phase2/accounts/account_error_mapper.dart';
import 'package:hocalist/data/phase2/accounts/account_transport.dart';
import 'package:hocalist/data/phase2/accounts/supabase_account_transport.dart';
import 'package:hocalist/domain/phase2/phase2.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_http_backend.dart';

void main() {
  late SyntheticAccountBackend backend;
  const mapper = AccountErrorMapper();

  setUp(() {
    backend = SyntheticAccountBackend();
    backend.tableRows['memberships'] = [
      {
        'id': '11111111-1111-1111-1111-111111111111',
        'user_id': syntheticUserA,
        'role': 'buyer',
        'status': 'active',
        'revision': 1,
        'created_at': '2026-05-01T00:00:00+00:00',
        'updated_at': '2026-05-01T00:00:00+00:00',
      },
    ];
  });

  Future<SupabaseClient> signedInClient({
    String email = 'user-a@example.com',
  }) async {
    final client = buildSyntheticSupabaseClient(backend.client());
    await client.auth.signInWithPassword(
      email: email,
      password: 'synthetic-password',
    );
    return client;
  }

  AccountTableQuery membershipsQuery({
    String? userId,
    String? role,
    List<String> orderBy = const ['role'],
  }) {
    return AccountTableQuery(
      schema: 'hocalist',
      table: 'memberships',
      columns: AccountDataAdapter.membershipColumns,
      filters: [
        if (userId != null) AccountColumnFilter.equals('user_id', userId),
        if (role != null) AccountColumnFilter.equals('role', role),
      ],
      orderBy: orderBy,
    );
  }

  group('selectRows over the real SDK', () {
    test(
      'restored expired session refreshes before pinning the request token',
      () async {
        final client = buildSyntheticSupabaseClient(backend.client());
        final restored = backend.issueSession(syntheticUserA);
        final expiredToken = restored['access_token'];
        await client.auth.setInitialSession(jsonEncode(restored));
        // Synthetic tokens have no JWT exp; emulate the expiry decoded from a
        // persisted real JWT without changing refresh-token ownership.
        client.auth.currentSession!.expiresAt =
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120;
        expect(client.auth.currentSession!.isExpired, isTrue);
        backend.onRequest = (request) async {
          if (!request.url.path.startsWith('/rest/')) return;
          if (request.headers['Authorization'] == 'Bearer $expiredToken') {
            backend.tableErrorOverrides['memberships'] = http.Response(
              jsonEncode({'code': 'PGRST301', 'message': 'JWT expired'}),
              401,
            );
          } else {
            backend.tableErrorOverrides.remove('memberships');
          }
        };
        final result = await SupabaseAccountTransport(
          client,
        ).selectRows(membershipsQuery(userId: syntheticUserA));
        expect(client.auth.currentSession!.accessToken, isNot(expiredToken));
        expect(result, isA<AccountTransportData>());
        expect(
          backend.restRequests.single.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
        await client.dispose();
      },
    );

    test('sends method, path, headers, columns, filters and order', () async {
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);
      final token = client.auth.currentSession!.accessToken;

      final response = await transport.selectRows(
        membershipsQuery(userId: syntheticUserA),
      );

      expect(response, isA<AccountTransportData>());
      final request = backend.restRequests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/memberships');
      expect(
        request.url.queryParameters['select'],
        'id,user_id,role,status,revision,created_at,updated_at',
      );
      expect(request.url.queryParameters['user_id'], 'eq.$syntheticUserA');
      expect(request.url.queryParameters['order'], 'role.asc.nullslast');
      expect(request.headers['Accept-Profile'], 'hocalist');
      expect(request.headers['apikey'], syntheticPublishableKey);
      expect(request.headers['Authorization'], 'Bearer $token');
      expect(backend.userForToken(token), syntheticUserA);
    });

    test('supports an is-null filter without an order', () async {
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response = await transport.selectRows(
        AccountTableQuery(
          schema: 'hocalist',
          table: 'memberships',
          columns: AccountDataAdapter.membershipColumns,
          filters: [const AccountColumnFilter.isNull('user_id')],
        ),
      );

      expect(response, isA<AccountTransportData>());
      final request = backend.restRequests.single;
      expect(request.url.queryParameters['user_id'], 'is.null');
      expect(request.url.queryParameters.containsKey('order'), isFalse);
    });

    test('never issues a request when signed out', () async {
      final client = buildSyntheticSupabaseClient(backend.client());
      final transport = SupabaseAccountTransport(client);

      final response = await transport.selectRows(membershipsQuery());

      expect(response, isA<AccountTransportError>());
      expect(
        (response as AccountTransportError).kind,
        AccountTransportErrorKind.unauthorized,
      );
      expect(backend.restRequests, isEmpty);
    });
  });

  group('callAccountCommand over the real SDK', () {
    test('sends the exact RPC body, path and headers', () async {
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);
      final token = client.auth.currentSession!.accessToken;

      final response = await transport.callAccountCommand(
        schema: 'hocalist',
        function: 'account_command',
        operation: 'profile.update',
        key: 'key-1',
        input: <String, Object?>{
          'profile_id': '11111111-1111-1111-1111-111111111111',
          'expected_revision': 1,
          'display_name': 'Maya Chen',
          'profile_note': null,
        },
      );

      expect(response, isA<AccountTransportData>());
      final request = backend.restRequests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/account_command');
      expect(request.headers['Content-Profile'], 'hocalist');
      expect(request.headers['Authorization'], 'Bearer $token');
      expect(jsonDecode(request.body), {
        'p_operation': 'profile.update',
        'p_key': 'key-1',
        'p_input': {
          'profile_id': '11111111-1111-1111-1111-111111111111',
          'expected_revision': 1,
          'display_name': 'Maya Chen',
          'profile_note': null,
        },
      });
    });
  });

  group('local route rejection', () {
    late SupabaseAccountTransport transport;

    setUp(() async {
      final client = await signedInClient();
      transport = SupabaseAccountTransport(client);
    });

    test('rejects unsupported schema, table and function', () async {
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'public',
            table: 'memberships',
            columns: AccountDataAdapter.membershipColumns,
          ),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'hocalist',
            table: 'profiles',
            columns: const ['id'],
          ),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        transport.callAccountCommand(
          schema: 'hocalist',
          function: 'other_command',
          operation: 'onboard',
          key: 'k',
          input: const {},
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        transport.callAccountCommand(
          schema: 'hocalist',
          function: 'account_command',
          operation: 'membership.delete',
          key: 'k',
          input: const {},
        ),
        throwsUnsupportedError,
      );
      expect(backend.restRequests, isEmpty);
    });

    test('rejects unsupported columns, filters and order fields', () async {
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'hocalist',
            table: 'memberships',
            columns: const ['id', 'password_hash'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'hocalist',
            table: 'memberships',
            columns: AccountDataAdapter.membershipColumns,
            filters: [AccountColumnFilter.equals('status', 'active')],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'hocalist',
            table: 'memberships',
            columns: AccountDataAdapter.membershipColumns,
            orderBy: const ['created_at'],
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        transport.selectRows(
          AccountTableQuery(
            schema: 'hocalist',
            table: 'memberships',
            columns: const [],
          ),
        ),
        throwsArgumentError,
      );
      expect(backend.restRequests, isEmpty);
    });
  });

  group('SDK error mapping through the transport', () {
    test('401 and PGRST301 become authentication failures', () async {
      backend.tableErrorOverrides['memberships'] = http.Response(
        jsonEncode({'message': 'JWT expired', 'code': 'PGRST301'}),
        401,
      );
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response = await transport.selectRows(
        membershipsQuery(userId: syntheticUserA),
      );
      final error = mapper.map(
        response as AccountTransportError,
        operation: 'memberships.select',
      );

      expect((response).kind, AccountTransportErrorKind.unauthorized);
      expect(error, isA<PermissionDeniedError>());
      expect((error as PermissionDeniedError).action, 'authenticate');
    });

    test('403 becomes a permission failure and 42501 keeps its code', () async {
      backend.tableErrorOverrides['memberships'] = http.Response(
        jsonEncode({'message': 'permission denied'}),
        403,
      );
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final forbidden =
          await transport.selectRows(membershipsQuery(userId: syntheticUserA))
              as AccountTransportError;
      expect(forbidden.kind, AccountTransportErrorKind.server);
      expect(forbidden.code, '403');
      expect(forbidden.statusCode, 403);
      expect(
        (mapper.map(forbidden, operation: 'memberships.select')
                as PermissionDeniedError)
            .action,
        'account_command',
      );

      backend.tableErrorOverrides['memberships'] = http.Response(
        jsonEncode({
          'message': 'permission denied for table memberships',
          'code': '42501',
        }),
        403,
      );
      final rlsDenied =
          await transport.selectRows(membershipsQuery(userId: syntheticUserA))
              as AccountTransportError;
      expect(rlsDenied.code, '42501');
      expect(rlsDenied.statusCode, isNull);
      expect(
        mapper.map(rlsDenied, operation: 'memberships.select'),
        isA<PermissionDeniedError>(),
      );
    });

    test('SQLSTATE 22023 becomes a validation failure', () async {
      backend.commandErrorOverrides['profile.update'] = http.Response(
        jsonEncode({'message': 'invalid_display_name', 'code': '22023'}),
        400,
      );
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response =
          await transport.callAccountCommand(
                schema: 'hocalist',
                function: 'account_command',
                operation: 'profile.update',
                key: 'key-1',
                input: const {'display_name': ''},
              )
              as AccountTransportError;
      final error = mapper.map(response, operation: 'account_command');

      expect(error, isA<ValidationError>());
      expect((error as ValidationError).issues.single.field, 'display_name');
    });

    test('a 500 response is retryable', () async {
      backend.tableErrorOverrides['memberships'] = http.Response(
        jsonEncode({'message': 'boom'}),
        500,
      );
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response =
          await transport.selectRows(membershipsQuery(userId: syntheticUserA))
              as AccountTransportError;

      expect(response.code, '500');
      expect(response.statusCode, 500);
      expect(response.retryable, isTrue);
      final error = mapper.map(response, operation: 'memberships.select');
      expect(error.kind, RepositoryFailureKind.server);
      expect(error.debugMessage.contains('boom'), isFalse);
    });

    test('a timeout is a connectivity failure, not a commit claim', () async {
      backend.onRequest = (request) async {
        if (request.url.path.startsWith('/rest/v1/')) {
          throw TimeoutException('synthetic timeout');
        }
      };
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response =
          await transport.selectRows(membershipsQuery(userId: syntheticUserA))
              as AccountTransportError;

      expect(response.kind, AccountTransportErrorKind.connectivity);
      expect(response.retryable, isTrue);
      expect(
        mapper.map(response, operation: 'memberships.select').kind,
        RepositoryFailureKind.network,
      );
    });

    test('a 2xx non-JSON payload becomes a malformed response', () async {
      backend.tableErrorOverrides['memberships'] = http.Response(
        '<html>proxy error</html>',
        200,
      );
      final client = await signedInClient();
      final transport = SupabaseAccountTransport(client);

      final response =
          await transport.selectRows(membershipsQuery(userId: syntheticUserA))
              as AccountTransportError;
      final error = mapper.map(response, operation: 'memberships.select');

      expect(response.statusCode, 200);
      expect(error, isA<MalformedResponseError>());
      expect((error as MalformedResponseError).detail, 'payload');
    });
  });
}
