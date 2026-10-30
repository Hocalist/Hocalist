/// Real-mode commercial ledger reads for the app wallet surfaces.
///
/// Every load comes from an authoritative server read (`commercial_credit_wallet`,
/// `commercial_reward_wallet`, `commercial_sale_history`, `commercial_sale_detail`).
/// The backend never computes a balance, a quota or a reward locally and never
/// converts a failure into a fabricated success. Deployment gate:
/// [createConfiguredCommercialWalletBackend] returns null unless the reviewed
/// commercial_completion bundle is applied and `enabled` is true.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/phase2/commercial/commercial.dart';

class CommercialRpcException implements Exception {
  const CommercialRpcException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'CommercialRpcException($code: $message)';
}

class CommercialUnavailableException implements Exception {
  const CommercialUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'CommercialUnavailableException($message)';
}

abstract interface class CommercialWalletBackend {
  Future<CreditWalletView> loadCreditWallet();

  Future<RewardWalletView> loadRewardWallet();

  Future<List<SaleHistoryEntryView>> loadSaleHistory({
    DateTime? beforeTime,
    String? beforeId,
  });

  Future<SaleDetailView> loadSaleDetail(String outcomeId);
}

abstract interface class CommercialDealSummaryBackend {
  Future<DealSummaryView> loadDealSummary();
}

abstract interface class CommercialSellerHomeBackend {
  Future<SellerHomeSummaryView> loadSellerHomeSummary();
}

class Phase2CommercialWalletBackend
    implements CommercialWalletBackend, CommercialDealSummaryBackend, CommercialSellerHomeBackend {
  Phase2CommercialWalletBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String creditWalletFunction = 'commercial_credit_wallet';
  static const String rewardWalletFunction = 'commercial_reward_wallet';
  static const String saleHistoryFunction = 'commercial_sale_history';
  static const String saleDetailFunction = 'commercial_sale_detail';
  static const Set<String> allowedFunctions = {
    creditWalletFunction,
    rewardWalletFunction,
    saleHistoryFunction,
    saleDetailFunction,
    'commercial_deal_summary',
    'seller_home_summary',
  };

  final Future<Map<String, Object?>> Function(
    String function,
    Map<String, Object?> params,
  )
  rpc;
  final String? Function() identity;

  @override
  Future<SellerHomeSummaryView> loadSellerHomeSummary() => _parse(() async =>
    SellerHomeSummaryView.fromJson(await _call('seller_home_summary',const {})));

  @override
  Future<DealSummaryView> loadDealSummary() => _parse(
    () async => DealSummaryView.fromJson(
      await _call('commercial_deal_summary', const {}),
    ),
  );

  @override
  Future<CreditWalletView> loadCreditWallet() async => _parse(
    () async =>
        CreditWalletView.fromJson(await _call(creditWalletFunction, const {})),
  );

  @override
  Future<RewardWalletView> loadRewardWallet() async => _parse(
    () async =>
        RewardWalletView.fromJson(await _call(rewardWalletFunction, const {})),
  );

  @override
  Future<List<SaleHistoryEntryView>> loadSaleHistory({
    DateTime? beforeTime,
    String? beforeId,
  }) async {
    if ((beforeTime == null) != (beforeId == null)) {
      throw const CommercialUnavailableException('Invalid history cursor.');
    }
    final data = await _call(saleHistoryFunction, {
      'p_before_time': ?beforeTime?.toUtc().toIso8601String(),
      'p_before_id': ?beforeId,
    });
    final rows = data['items'];
    if (rows is! List || rows.length > 25) {
      throw const CommercialUnavailableException(
        'The sale history response was invalid.',
      );
    }
    return _parse(
      () async => List.unmodifiable(
        rows.map((row) {
          if (row is! Map) {
            throw const CommercialUnavailableException(
              'The sale history response was invalid.',
            );
          }
          return SaleHistoryEntryView.fromJson(Map<String, Object?>.from(row));
        }),
      ),
    );
  }

  @override
  Future<SaleDetailView> loadSaleDetail(String outcomeId) async {
    if (outcomeId.isEmpty) {
      throw const CommercialUnavailableException('Invalid sale reference.');
    }
    return _parse(
      () async => SaleDetailView.fromJson(
        await _call(saleDetailFunction, {'p_outcome': outcomeId}),
      ),
    );
  }

  Future<T> _parse<T>(Future<T> Function() decode) async {
    try {
      return await decode();
    } on CommercialContractError {
      throw const CommercialUnavailableException(
        'The commercial ledger response was invalid.',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const CommercialUnavailableException(
        'Commercial ledgers are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const CommercialUnavailableException(
        'Sign in to view your ledgers.',
      );
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
        'The commercial ledger response was invalid.',
      );
    } on CommercialRpcException catch (error) {
      if (error.message.contains('wallet_access_denied') ||
          error.message.contains('sale_access_denied')) {
        throw const CommercialUnavailableException(
          'This ledger is not available for your account.',
        );
      }
      throw CommercialUnavailableException(error.message);
    } catch (_) {
      throw const CommercialUnavailableException(
        'The commercial ledger could not be loaded. Please retry.',
      );
    }
  }
}

/// Explicit read capability for reviewed deployments. The localhost flag is
/// retained as a preview default; mobile builds need not impersonate localhost.
const bool kCommercialReadsEnabled = bool.fromEnvironment(
  'HOCALIST_COMMERCIAL_READS',
  defaultValue: bool.fromEnvironment('HOCALIST_LOCAL_WEB_TEST'),
);

CommercialWalletBackend? createConfiguredCommercialWalletBackend({
  bool enabled = kCommercialReadsEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2CommercialWalletBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2CommercialWalletBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const CommercialUnavailableException(
              'The commercial ledger response was invalid.',
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
