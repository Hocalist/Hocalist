/// Real-mode buyer withdrawal seam.
///
/// Provider-neutral: it reads the authoritative earned/reserved balance and
/// submits a withdrawal intent through the reviewed `withdrawal_status` and
/// `withdrawal_request` RPCs. No provider is called and no payout success is
/// fabricated; the panel renders the server's processing/failed/paid states.
///
/// Deployment gate: [createConfiguredWithdrawalBackend] returns null unless the
/// reviewed upgrade bundle is deployed and `enabled` is true. Tests inject the
/// [rpc] fake.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class WithdrawalRpcException implements Exception {
  const WithdrawalRpcException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'WithdrawalRpcException($code: $message)';
}

class WithdrawalUnavailableException implements Exception {
  const WithdrawalUnavailableException(
    this.message, {
    this.outcomeUncertain = false,
  });

  final String message;
  final bool outcomeUncertain;

  @override
  String toString() => 'WithdrawalUnavailableException($message)';
}

/// One withdrawal row as the server reports it. Never constructed locally.
class WithdrawalRequestView {
  const WithdrawalRequestView({
    required this.id,
    required this.amountMinor,
    required this.feeMinor,
    required this.netMinor,
    required this.status,
    this.failureReason,
    required this.createdAt,
  });

  final String id;
  final int amountMinor;
  final int feeMinor;
  final int netMinor;

  /// `processing`, `failed` or `paid`.
  final String status;
  final String? failureReason;
  final DateTime createdAt;

  bool get isProcessing => status == 'processing';
  bool get isFailed => status == 'failed';
  bool get isPaid => status == 'paid';
}

class WithdrawalStatusView {
  const WithdrawalStatusView({
    required this.minimumMinor,
    required this.feeMinor,
    required this.earnedMinor,
    required this.processingMinor,
    required this.availableMinor,
    required this.emailVerified,
    required this.phoneVerified,
    required this.requests,
  });

  final int minimumMinor;
  final int feeMinor;
  final int earnedMinor;
  final int processingMinor;
  final int availableMinor;

  /// Verified through Auth, never through editable profile text.
  final bool emailVerified;
  final bool phoneVerified;
  final List<WithdrawalRequestView> requests;

  bool get contactVerified => emailVerified && phoneVerified;

  /// The explicit net amount for one gross request at the current fee.
  int netFor(int amountMinor) => amountMinor - feeMinor;

  @override
  String toString() =>
      'WithdrawalStatusView(available: $availableMinor, requests: ${requests.length})';
}

abstract interface class WithdrawalBackend {
  Future<WithdrawalStatusView> loadStatus();

  Future<WithdrawalRequestView> requestWithdrawal({
    required int amountMinor,
    required String operationKey,
  });
}

class Phase2WithdrawalBackend implements WithdrawalBackend {
  Phase2WithdrawalBackend({required this.rpc, required this.identity});

  static const String schema = 'hocalist';
  static const String statusFunction = 'withdrawal_status';
  static const String requestFunction = 'withdrawal_request';
  static const Set<String> allowedFunctions = {statusFunction, requestFunction};

  final Future<Map<String, Object?>> Function(
    String function,
    Map<String, Object?> params,
  )
  rpc;
  final String? Function() identity;

  @override
  Future<WithdrawalStatusView> loadStatus() async {
    final data = await _call(statusFunction, const {});
    final minimum = data['minimum_minor'];
    final fee = data['fee_minor'];
    final earned = data['earned_minor'];
    final processing = data['processing_minor'];
    final available = data['available_minor'];
    final email = data['email_verified'];
    final phone = data['phone_verified'];
    final rows = data['requests'];
    if (minimum is! int ||
        fee is! int ||
        earned is! int ||
        processing is! int ||
        available is! int ||
        email is! bool ||
        phone is! bool ||
        rows is! List) {
      throw const WithdrawalUnavailableException(
        'The withdrawal status response was invalid.',
      );
    }
    final requests = <WithdrawalRequestView>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const WithdrawalUnavailableException(
          'The withdrawal status response was invalid.',
        );
      }
      requests.add(_decodeRequest(Map<String, Object?>.from(row)));
    }
    return WithdrawalStatusView(
      minimumMinor: minimum,
      feeMinor: fee,
      earnedMinor: earned,
      processingMinor: processing,
      availableMinor: available,
      emailVerified: email,
      phoneVerified: phone,
      requests: List.unmodifiable(requests),
    );
  }

  @override
  Future<WithdrawalRequestView> requestWithdrawal({
    required int amountMinor,
    required String operationKey,
  }) async {
    final data = await _call(requestFunction, {
      'p_key': operationKey,
      'p_amount_minor': amountMinor,
    });
    final id = data['withdrawal_id'];
    if (id is! String) {
      throw const WithdrawalUnavailableException(
        'The withdrawal response was invalid.',
      );
    }
    return WithdrawalRequestView(
      id: id,
      amountMinor: data['amount_minor'] as int,
      feeMinor: data['fee_minor'] as int,
      netMinor: data['net_minor'] as int,
      status: 'processing',
      createdAt: DateTime.now().toUtc(),
    );
  }

  WithdrawalRequestView _decodeRequest(Map<String, Object?> row) {
    final id = row['id'];
    final amount = row['amount_minor'];
    final fee = row['fee_minor'];
    final net = row['net_minor'];
    final status = row['status'];
    final created = row['created_at'];
    if (id is! String ||
        amount is! int ||
        fee is! int ||
        net is! int ||
        status is! String ||
        !const {'processing', 'failed', 'paid'}.contains(status) ||
        created is! String ||
        DateTime.tryParse(created) == null) {
      throw const WithdrawalUnavailableException(
        'The withdrawal status response was invalid.',
      );
    }
    return WithdrawalRequestView(
      id: id,
      amountMinor: amount,
      feeMinor: fee,
      netMinor: net,
      status: status,
      failureReason: row['failure_reason'] is String
          ? row['failure_reason']! as String
          : null,
      createdAt: DateTime.parse(created).toUtc(),
    );
  }

  Future<Map<String, Object?>> _call(
    String function,
    Map<String, Object?> params,
  ) async {
    if (!allowedFunctions.contains(function)) {
      throw const WithdrawalUnavailableException(
        'Withdrawals are unavailable.',
      );
    }
    final captured = identity();
    if (captured == null || captured.isEmpty) {
      throw const WithdrawalUnavailableException('Sign in to withdraw.');
    }
    try {
      final data = await rpc(function, params);
      if (identity() != captured) {
        throw const WithdrawalUnavailableException(
          'Your session changed. Sign in again.',
        );
      }
      return data;
    } on WithdrawalRpcException catch (error) {
      if (error.code == 'P0001' &&
          error.message.contains('contact_verification_required')) {
        throw const WithdrawalUnavailableException(
          'Verify your email and phone before withdrawing.',
        );
      }
      if (error.code == 'P0001' && error.message.contains('below_minimum')) {
        throw const WithdrawalUnavailableException(
          'The minimum withdrawal is not met.',
        );
      }
      if (error.code == 'P0001' &&
          error.message.contains('insufficient_earned_balance')) {
        throw const WithdrawalUnavailableException(
          'That amount is more than your available earned balance.',
        );
      }
      throw WithdrawalUnavailableException(
        error.message,
        outcomeUncertain: error.statusCode == null || error.statusCode! >= 500,
      );
    } on WithdrawalUnavailableException {
      rethrow;
    } catch (_) {
      throw const WithdrawalUnavailableException(
        'The withdrawal could not be confirmed. Retry to check it safely.',
        outcomeUncertain: true,
      );
    }
  }
}

/// Set true only after the reviewed upgrade bundle is applied and provider
/// execution is approved. Payout provider eligibility stays a coordinator gate.
const bool kWithdrawalsEnabled = false;

/// Status reads do not enable withdrawal requests or provider execution.
const bool kWithdrawalReadsEnabled = bool.fromEnvironment(
  'HOCALIST_WITHDRAWAL_READS',
  defaultValue: bool.fromEnvironment('HOCALIST_LOCAL_WEB_TEST'),
);

Future<WithdrawalStatusView> Function()?
createConfiguredWithdrawalStatusLoader({
  bool enabled = kWithdrawalReadsEnabled,
}) {
  if (!enabled) return null;
  return createConfiguredWithdrawalBackend(enabled: true)?.loadStatus;
}

WithdrawalBackend? createConfiguredWithdrawalBackend({
  bool enabled = kWithdrawalsEnabled,
}) {
  if (!enabled) return null;
  try {
    final client = Supabase.instance.client;
    return Phase2WithdrawalBackend(
      identity: () => client.auth.currentUser?.id,
      rpc: (function, params) async {
        try {
          final data = await client
              .schema(Phase2WithdrawalBackend.schema)
              .rpc(function, params: params);
          if (data is! Map) {
            throw const WithdrawalUnavailableException(
              'The withdrawal response was invalid.',
            );
          }
          return Map<String, Object?>.from(data);
        } on PostgrestException catch (error) {
          throw WithdrawalRpcException(
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
