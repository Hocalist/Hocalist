import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/marketplace/supabase_marketplace_transport.dart';
import '../accounts/support/supabase_http_backend.dart';

void main() {
  test(
    'deployed module RPCs reach real SDK with scoped schema and session',
    () async {
      final auth = SyntheticAccountBackend().client();
      final requests = <http.Request>[];
      final client = buildSyntheticSupabaseClient(
        MockClient((request) async {
          if (request.url.path.startsWith('/auth/')) {
            final forwarded = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await auth.send(forwarded));
          }
          requests.add(request);
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'user-a@example.com',
        password: 'synthetic',
      );
      final transport = SupabaseMarketplaceTransport(client);
      for (final name in [
        'marketplace_timezones',
        'meeting_list',
        'meeting_detail',
        'meeting_propose',
        'meeting_respond',
        'meeting_reschedule_propose',
        'meeting_cancel',
        'notification_inbox',
        'notification_mark_read',
        'notification_mark_all_read',
        'notification_preferences',
        'notification_preferences_update',
      ]) {
        final result = await transport.callMarketplaceRpc(
          MarketplaceRpcCall(
            schema: 'hocalist',
            function: name,
            params: const {'sentinel': 'input'},
          ),
        );
        expect(result, isA<MarketplaceTransportData>(), reason: name);
        expect(requests.last.url.path, '/rest/v1/rpc/$name');
        expect(requests.last.headers['Content-Profile'], 'hocalist');
        expect(
          requests.last.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
        expect(jsonDecode(requests.last.body), {'sentinel': 'input'});
      }
      final count = requests.length;
      await expectLater(
        transport.callMarketplaceRpc(
          MarketplaceRpcCall(
            schema: 'hocalist',
            function: 'notification_emit',
            params: {},
          ),
        ),
        throwsUnsupportedError,
      );
      expect(requests.length, count);
      await client.auth.signOut();
      await transport.callMarketplaceRpc(
        MarketplaceRpcCall(
          schema: 'hocalist',
          function: 'meeting_list',
          params: {},
        ),
      );
      expect(requests.length, count);
    },
  );
}
