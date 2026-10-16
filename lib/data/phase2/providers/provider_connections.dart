import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/account/account_auth_gateway.dart';
import '../accounts/account_adapter.dart';
import '../accounts/account_composition.dart';
import 'hocalist_auth_service.dart';
import 'hocalist_push_service.dart';
import 'provider_runtime.dart';
import 'stripe_test_billing_service.dart';
import 'supabase_account_auth_gateway.dart';

/// One composition point for the real account UI after account rollout.
/// It does not replace the prototype repository or manufacture authenticated UI.
class HocalistProviderConnections implements HocalistAccountServices {
  HocalistProviderConnections._(this.client, {required String publishableKey})
    : accounts = createAccountDataAdapter(client: client),
      accountAuth = SupabaseAccountAuthGateway(
        client,
        publishableKey: publishableKey,
      ),
      auth = HocalistAuthService(client, publishableKey: publishableKey),
      push = HocalistPushService(client),
      billing = StripeTestBillingService(client);

  final SupabaseClient client;
  @override
  final AccountDataAdapter accounts;
  @override
  final SupabaseAccountAuthGateway accountAuth;
  final HocalistAuthService auth;
  final HocalistPushService push;
  final StripeTestBillingService billing;

  @override
  Future<void> Function() get disablePush => push.disableBeforeLogout;

  static Future<HocalistProviderConnections> initialize({
    required String publicKey,
  }) async {
    final client = await initializeHocalistProviders(publicKey: publicKey);
    return HocalistProviderConnections._(client, publishableKey: publicKey);
  }

  Future<void> logout() => auth.logout(disablePush: push.disableBeforeLogout);
  Future<void> dispose() => push.dispose();
}
