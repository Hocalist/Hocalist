import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'provider_runtime.dart';

class StripeTestBillingService {
  StripeTestBillingService(this.client);
  final SupabaseClient client;

  /// Caller retains this key for retries; never create another key after a timeout.
  Future<Uri> startCheckout({
    required String plan,
    required String idempotencyKey,
  }) async {
    if (!{'pro', 'elite'}.contains(plan) ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(idempotencyKey)) {
      throw const ProviderOperationException('invalid_checkout');
    }
    final fence = ProviderSessionFence(client);
    try {
      fence.check();
      final response = await client.functions.invoke(
        'hocalist-stripe-test-checkout',
        headers: {'Authorization': 'Bearer ${await fence.freshToken()}'},
        body: {'plan': plan, 'idempotency_key': idempotencyKey},
      );
      fence.check();
      final data = response.data;
      if (response.status != 200 || data is! Map || data['url'] is! String) {
        throw const ProviderOperationException('checkout_unavailable');
      }
      final uri = Uri.parse(data['url'] as String);
      if (uri.scheme != 'https' ||
          uri.host != 'checkout.stripe.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort) {
        throw const ProviderOperationException('invalid_checkout_destination');
      }
      return uri;
    } on ProviderOperationException {
      rethrow;
    } catch (_) {
      throw const ProviderOperationException('checkout_unavailable');
    }
  }

  Future<void> openCheckout({
    required String plan,
    required String idempotencyKey,
  }) async {
    final fence = ProviderSessionFence(client);
    final url = await startCheckout(plan: plan, idempotencyKey: idempotencyKey);
    fence.check();
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw const ProviderOperationException('browser_not_opened');
    }
  }

  /// Refresh after app resume. Neither the return page nor URL query grants access.
  Future<Map<String, dynamic>?> fetchStatus() async {
    final fence = ProviderSessionFence(client);
    try {
      fence.check();
      final result = await client
          .schema('hocalist')
          .rpc('stripe_test_billing_status')
          .setHeader('Authorization', 'Bearer ${await fence.freshToken()}');
      fence.check();
      if (result == null) return null;
      if (result is! Map ||
          !{'free', 'pro', 'elite'}.contains(result['plan'])) {
        throw const ProviderOperationException('invalid_billing_response');
      }
      return Map<String, dynamic>.unmodifiable(result);
    } on ProviderOperationException {
      rethrow;
    } catch (_) {
      throw const ProviderOperationException('billing_unavailable');
    }
  }
}
