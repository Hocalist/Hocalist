import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/commercial_wallet_backend.dart'
    show CommercialRpcException, CommercialUnavailableException;
import 'package:hocalist/data/phase2/commercial/entitlement_backend.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';

import 'support/commercial_payloads.dart';

void main() {
  test('entitlement and preview reads are typed and server-sourced', () async {
    final calls = <String>[];
    final backend = Phase2EntitlementBackend(
      identity: () => 'seller-1',
      rpc: (function, params) async {
        calls.add('$function:${params['p_plan'] ?? ''}');
        if (function == Phase2EntitlementBackend.entitlementFunction) {
          return entitlementJson();
        }
        return planPreviewJson(plan: params['p_plan'] as String? ?? 'free');
      },
    );
    final entitlement = await backend.loadEntitlement();
    expect(entitlement.effectivePlan, PlanCode.free);
    expect(entitlement.effectiveSource, EntitlementSource.free);
    expect(entitlement.policy.earnedProThreshold, 7);
    expect(entitlement.policy.calendarConfigured, false);
    final preview = await backend.loadPlanPreview(PlanCode.pro);
    expect(preview.planCode, PlanCode.pro);
    expect(preview.downgrade.policyConfigured, false);
    expect(calls, ['account_entitlement:', 'entitlement_plan_preview:pro']);
  });

  test('a session replacement during an entitlement read is refused', () async {
    String? user = 'seller-1';
    final backend = Phase2EntitlementBackend(
      identity: () => user,
      rpc: (function, params) async {
        user = 'seller-2';
        return entitlementJson();
      },
    );
    await expectLater(
      backend.loadEntitlement(),
      throwsA(isA<CommercialUnavailableException>()),
    );
  });

  test('an access denial maps to a typed unavailable error', () async {
    final backend = Phase2EntitlementBackend(
      identity: () => 'buyer-1',
      rpc: (function, params) async => throw const CommercialRpcException(
        'entitlement_access_denied',
        code: '42501',
      ),
    );
    await expectLater(
      backend.loadEntitlement(),
      throwsA(
        isA<CommercialUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('not available'),
        ),
      ),
    );
  });

  test('a malformed entitlement response is never rendered as a plan', () async {
    final backend = Phase2EntitlementBackend(
      identity: () => 'seller-1',
      rpc: (function, params) async => {
        ...entitlementJson(),
        'effective_plan': 'gold',
      },
    );
    await expectLater(
      backend.loadEntitlement(),
      throwsA(isA<CommercialUnavailableException>()),
    );
  });

  test('the configured entitlement backend stays off until enabled', () {
    expect(kEntitlementsEnabled, false);
    expect(createConfiguredEntitlementBackend(), isNull);
  });
}
