import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_composition.dart';
import 'package:hocalist/data/phase2/accounts/supabase_account_session.dart';
import 'package:hocalist/domain/phase2/phase2.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/supabase_http_backend.dart';

void main() {
  late SyntheticAccountBackend backend;

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

  Future<void> replaceSessionWithB(SupabaseClient client) async {
    await client.auth.signInWithPassword(
      email: 'user-b@example.com',
      password: 'synthetic-password',
    );
  }

  group('live session', () {
    test('reads the SDK auth state instead of a cached identity', () async {
      final client = buildSyntheticSupabaseClient(backend.client());
      final session = SupabaseAccountSession(client);

      expect(session.currentUserId, isNull);

      await client.auth.signInWithPassword(
        email: 'user-a@example.com',
        password: 'synthetic-password',
      );
      expect(session.currentUserId, syntheticUserA);

      await replaceSessionWithB(client);
      expect(session.currentUserId, syntheticUserB);

      await client.auth.signOut();
      expect(session.currentUserId, isNull);
    });
  });

  group('session fence', () {
    test('discards an in-flight result after account replacement', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      final tokenA = client.auth.currentSession!.accessToken;
      backend.onRequest = (request) async {
        if (request.url.path == '/rest/v1/memberships') {
          backend.onRequest = null;
          await replaceSessionWithB(client);
        }
      };

      final result = await adapter.fetchMemberships();

      final error = result.errorOrNull;
      expect(error, isA<PermissionDeniedError>());
      expect((error! as PermissionDeniedError).action, 'session_changed');
      final request = backend.restRequests.single;
      expect(request.headers['Authorization'], 'Bearer $tokenA');
    });

    test('stops a multi-step read before the second request', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      backend.tableRows['role_profiles'] = [
        {
          'membership_id': '11111111-1111-1111-1111-111111111111',
          'display_name': 'Maya Chen',
          'area_label': null,
          'profile_note': null,
          'preferred_meetup_type': null,
          'service_radius_miles': null,
          'pickup_availability': null,
          'revision': 1,
          'created_at': '2026-05-01T00:00:00+00:00',
          'updated_at': '2026-05-01T00:00:00+00:00',
        },
      ];
      backend.onRequest = (request) async {
        if (request.url.path == '/rest/v1/memberships') {
          backend.onRequest = null;
          await replaceSessionWithB(client);
        }
      };

      final result = await adapter.fetchRoleProfile(role: HocalistRole.buyer);

      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
      expect(
        backend.restRequests.where(
          (request) => request.url.path == '/rest/v1/role_profiles',
        ),
        isEmpty,
      );
    });

    test('a queued edit is never sent with the replacement token', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      final tokenA = client.auth.currentSession!.accessToken;
      backend.onRequest = (request) async {
        if (request.url.path == '/rest/v1/rpc/account_command') {
          backend.onRequest = null;
          await replaceSessionWithB(client);
        }
      };

      final result = await adapter.updateContact(
        UpdateContactCommand(
          expectedRevision: 1,
          phone: const PatchSet<String>('+1 914 555 0182'),
          idempotencyKey: 'edit-1',
        ),
      );

      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'session_changed',
      );
      final request = backend.restRequests.single;
      expect(request.headers['Authorization'], 'Bearer $tokenA');
      expect(backend.userForToken(tokenA), syntheticUserA);
    });

    test('a signed-out call fails before any request', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      await client.auth.signOut();
      final restBefore = backend.restRequests.length;

      final result = await adapter.updateContact(
        UpdateContactCommand(
          expectedRevision: 1,
          city: const PatchSet<String>('Yonkers'),
          idempotencyKey: 'edit-2',
        ),
      );

      expect(
        (result.errorOrNull! as PermissionDeniedError).action,
        'authenticate',
      );
      expect(backend.restRequests.length, restBefore);
      expect(
        backend.restRequests.where(
          (request) => request.url.path.contains('/rpc/'),
        ),
        isEmpty,
      );
    });
  });

  group('token refresh', () {
    test('keeps the same identity working with the refreshed token', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      final firstToken = client.auth.currentSession!.accessToken;

      final first = await adapter.fetchMemberships();
      expect(first.isSuccess, isTrue);

      await client.auth.refreshSession();
      final secondToken = client.auth.currentSession!.accessToken;
      expect(secondToken, isNot(firstToken));

      final second = await adapter.fetchMemberships();
      expect(second.isSuccess, isTrue);
      expect(second.valueOrNull!.single.userId, syntheticUserA);

      final authorization = backend.restRequests
          .map((request) => request.headers['Authorization'])
          .toList();
      expect(authorization, ['Bearer $firstToken', 'Bearer $secondToken']);
    });
  });

  group('retries', () {
    test('a lost response retry reuses the same key through the SDK', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);
      var failed = false;
      backend.onRequest = (request) async {
        if (request.url.path == '/rest/v1/rpc/account_command' && !failed) {
          failed = true;
          throw http.ClientException('synthetic connection lost');
        }
      };
      final command = UpdateContactCommand(
        expectedRevision: 1,
        city: const PatchSet<String>('Yonkers'),
        idempotencyKey: 'retry-key-1',
      );

      final first = await adapter.updateContact(command);
      expect(first.errorOrNull, isA<NetworkError>());

      final second = await adapter.updateContact(command);
      expect(second.valueOrNull?.revision, 2);

      final bodies = backend.commandInputs;
      expect(bodies.length, 2);
      expect(bodies[0]['p_key'], 'retry-key-1');
      expect(bodies[1]['p_key'], 'retry-key-1');
      expect(bodies[0]['p_input'], bodies[1]['p_input']);
    });
  });

  group('composition', () {
    test('factory wires the SDK client to a working adapter', () async {
      final client = await signedInClient();
      final adapter = createAccountDataAdapter(client: client);

      final result = await adapter.fetchMemberships();

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.single.role, HocalistRole.buyer);
      expect(result.valueOrNull!.single.membershipId, isNotEmpty);
    });
  });
}
