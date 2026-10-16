/// Authoritative seller entitlement reads.
///
/// The plan and every benefit source are resolved by the server from verified
/// subscription/account records. The client cannot select a plan: this backend
/// only reads `account_entitlement` and the read-only `entitlement_plan_preview`.
/// Deployment gate: [createConfiguredEntitlementBackend] returns null unless
/// the reviewed commercial_completion bundle is applied and `enabled` is true.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/phase2/commercial/commercial.dart';
import 'commercial_wallet_backend.dart'
    show CommercialRpcException, CommercialUnavailableException;

class Phase2EntitlementBackend {
  Phase2EntitlementBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String entitlementFunction = 'account_entitlement';
  static const String previewFunction = 'entitlement_plan_preview';
  static const Set<String> allowedFunctions = {
    entitlementFunction,
    previewFunction,
  };

  final Future<Map<String, Object?>> Function(
    String function,
    Map<String, Object?> params,
  )
  rpc;
  final String? Function() identity;

  Future<SellerEntitlementView> loadEntitlement() async => _parse(
    () async => SellerEntitlementView.fromJson(
      await _call(entitlementFunction, const {}),
    ),
  );

  Future<PlanPreviewView> loadPlanPreview(PlanCode plan) async {
    final code = switch (plan) {
      PlanCode.free => 'free',
      PlanCode.pro => 'pro',
      PlanCode.elite => 'elite',
    };
    return _parse(
      () async => PlanPreviewView.fromJson(
        await _call(previewFunction, {'p_plan': code}),
      ),
    );
  }

  Future<T> _parse<T>(Future<T> Function() decode) async {
    try {
      return await decode();
    } on CommercialContractError {
      throw const CommercialUnavailableException(
        'The entitlement response was invalid.',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const CommercialUnavailableException(
        'Entitlements are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const CommercialUnavailableException('Sign in to view your plan.');
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const CommercialUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on CommercialUnavailableException {
      rethrow;
    } on CommercialContractError {
      throw const CommercialUnavailableException(
        'The entitlement response was invalid.',
      );
    } on CommercialRpcException catch (error) {
      if (error.message.contains('entitlement_access_denied')) {
        throw const CommercialUnavailableException(
          'Seller entitlements are not available for your account.',
        );
      }
      throw CommercialUnavailableException(error.message);
    } catch (_) {
      throw const CommercialUnavailableException(
        'Your plan could not be loaded. Please retry.',
      );
    }
  }
}

/// Set true only after the reviewed commercial_completion bundle is applied.
const bool kEntitlementsEnabled = bool.fromEnvironment('HOCALIST_ENTITLEMENTS');

Phase2EntitlementBackend? createConfiguredEntitlementBackend({
  bool enabled = kEntitlementsEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2EntitlementBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2EntitlementBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const CommercialUnavailableException(
              'The entitlement response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw CommercialRpcException(
            error.message,
            code: error.code,
            statusCode: error.code == null ? null : 400,
          );
        }
      },
    );
  } catch (_) {
    return null;
  }
}
