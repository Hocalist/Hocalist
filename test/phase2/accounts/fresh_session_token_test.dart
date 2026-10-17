import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/fresh_session_token.dart';
import 'package:hocalist/data/phase2/accounts/account_transport.dart';
import 'package:hocalist/data/phase2/accounts/supabase_account_transport.dart';
import 'package:hocalist/data/phase2/chat/chat_transport.dart';
import 'package:hocalist/data/phase2/chat/supabase_chat_transport.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/marketplace/supabase_marketplace_transport.dart';
import 'support/supabase_http_backend.dart';
import 'package:hocalist/data/phase2/providers/provider_runtime.dart';
import 'package:hocalist/data/phase2/providers/stripe_test_billing_service.dart';
import 'package:hocalist/data/phase2/providers/hocalist_push_service.dart';

void main() {
  test(
    'billing handoff refreshes a valid but nearly expired app session',
    () async {
      final backend = SyntheticAccountBackend();
      final client = buildSyntheticSupabaseClient(backend.client());
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(backend.issueSession(syntheticUserA)),
      );
      final oldToken = client.auth.currentSession!.accessToken;
      client.auth.currentSession!.expiresAt =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120;
      final fence = ProviderSessionFence(client);
      expect(
        await fence.freshToken(minimumValidity: const Duration(minutes: 30)),
        isNot(oldToken),
      );
      expect(client.auth.currentUser!.id, syntheticUserA);
    },
  );
  for (final provider in ['billing', 'notification lookup']) {
    test('$provider dispatch pins the refreshed Bearer token', () async {
      final backend = SyntheticAccountBackend();
      backend.commandResults[''] = {'plan': 'free'};
      backend.tableRows['notifications'] = [
        {'id': 'test-notification', 'user_id': syntheticUserA},
      ];
      final client = buildSyntheticSupabaseClient(backend.client());
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(backend.issueSession(syntheticUserA)),
      );
      final oldToken = client.auth.currentSession!.accessToken;
      client.auth.currentSession!.expiresAt = 1;
      if (provider == 'billing') {
        expect(await StripeTestBillingService(client).fetchStatus(), {
          'plan': 'free',
        });
      } else {
        expect(
          await HocalistPushService(
            client,
          ).fetchNotification('test-notification'),
          {'id': 'test-notification', 'user_id': syntheticUserA},
        );
      }
      expect(client.auth.currentSession!.accessToken, isNot(oldToken));
      expect(
        backend.restRequests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    });
  }

  test(
    'provider fence refreshes its initiating identity before pinning',
    () async {
      final backend = SyntheticAccountBackend();
      final client = buildSyntheticSupabaseClient(backend.client());
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(backend.issueSession(syntheticUserA)),
      );
      final oldToken = client.auth.currentSession!.accessToken;
      final fence = ProviderSessionFence(client);
      client.auth.currentSession!.expiresAt = 1;
      expect(await fence.freshToken(), isNot(oldToken));
      expect(await fence.freshToken(), client.auth.currentSession!.accessToken);
    },
  );

  test('queued provider fence cannot adopt a replacement identity', () async {
    final backend = SyntheticAccountBackend();
    final client = buildSyntheticSupabaseClient(backend.client());
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode(backend.issueSession(syntheticUserA)),
    );
    final fence = ProviderSessionFence(client);
    await client.auth.signInWithPassword(
      email: 'user-b@example.com',
      password: 'synthetic-password',
    );
    await expectLater(
      fence.freshToken(),
      throwsA(isA<ProviderOperationException>()),
    );
    expect(backend.restRequests, isEmpty);
  });

  for (final route in ['account', 'chat', 'marketplace']) {
    test('$route refreshes before pinning and dispatches once', () async {
      final backend = SyntheticAccountBackend();
      final client = buildSyntheticSupabaseClient(backend.client());
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(backend.issueSession(syntheticUserA)),
      );
      final oldToken = client.auth.currentSession!.accessToken;
      client.auth.currentSession!.expiresAt = 1;
      switch (route) {
        case 'account':
          expect(
            await SupabaseAccountTransport(client).callAccountCommand(
              schema: 'hocalist',
              function: 'account_command',
              operation: 'onboard',
              key: 'stable-intent',
              input: const {'role': 'buyer', 'display_name': 'Test'},
            ),
            isA<AccountTransportData>(),
          );
        case 'chat':
          await SupabaseChatTransport(client).callChatRpc(
            ChatRpcCall(
              schema: 'hocalist',
              function: 'chat_inbox',
              params: const {},
            ),
          );
        case 'marketplace':
          await SupabaseMarketplaceTransport(client).callMarketplaceRpc(
            MarketplaceRpcCall(
              schema: 'hocalist',
              function: 'marketplace_my_requests',
              params: const {},
            ),
          );
      }
      expect(client.auth.currentSession!.accessToken, isNot(oldToken));
      expect(
        backend.restRequests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
      expect(
        backend.requests.where(
          (r) => r.url.queryParameters['grant_type'] == 'refresh_token',
        ),
        hasLength(1),
      );
    });
  }

  test('replacement during refresh cancels the initiating operation', () async {
    final backend = SyntheticAccountBackend();
    final client = buildSyntheticSupabaseClient(backend.client());
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode(backend.issueSession(syntheticUserA)),
    );
    client.auth.currentSession!.expiresAt = 1;
    final entered = Completer<void>();
    final release = Completer<void>();
    backend.onRequest = (request) async {
      if (request.url.queryParameters['grant_type'] == 'refresh_token') {
        entered.complete();
        await release.future;
      }
    };
    final pending = freshSessionToken(client);
    await entered.future;
    await client.auth.signInWithPassword(
      email: 'user-b@example.com',
      password: 'synthetic-password',
    );
    release.complete();
    expect(await pending, isNull);
    expect(backend.restRequests, isEmpty);
  });

  test('simultaneous callers share the SDK refresh', () async {
    final backend = SyntheticAccountBackend();
    final client = buildSyntheticSupabaseClient(backend.client());
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode(backend.issueSession(syntheticUserA)),
    );
    client.auth.currentSession!.expiresAt = 1;
    final tokens = await Future.wait([
      freshSessionToken(client),
      freshSessionToken(client),
    ]);
    expect(tokens, everyElement(client.auth.currentSession!.accessToken));
    expect(
      backend.requests.where(
        (r) => r.url.queryParameters['grant_type'] == 'refresh_token',
      ),
      hasLength(1),
    );
  });
}
