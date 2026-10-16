// Withdrawal backend tests: authoritative decode, provider-neutral errors and
// the session fence. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/commercial/withdrawal_backend.dart';

Map<String, Object?> _statusJson({
  bool email = true,
  bool phone = true,
  int available = 5000,
  List<Map<String, Object?>>? requests,
}) => {
  'minimum_minor': 2000,
  'fee_minor': 250,
  'earned_minor': 5000,
  'processing_minor': 5000 - available,
  'available_minor': available,
  'email_verified': email,
  'phone_verified': phone,
  'requests': requests ?? const [],
};

void main() {
  test('status reads do not enable withdrawal execution', () {
    expect(kWithdrawalsEnabled, isFalse);
    expect(createConfiguredWithdrawalBackend(), isNull);
    expect(createConfiguredWithdrawalStatusLoader(enabled: false), isNull);
  });
  test('loadStatus decodes the settled terms and request states', () async {
    final calls = <String>[];
    final backend = Phase2WithdrawalBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add(function);
        return _statusJson(
          available: 2000,
          requests: [
            {
              'id': '80000000-0000-4000-8000-000000000001',
              'amount_minor': 3000,
              'fee_minor': 250,
              'net_minor': 2750,
              'status': 'failed',
              'failure_reason': 'account closed',
              'created_at': '2026-05-01T00:00:00+00:00',
            },
          ],
        );
      },
    );
    final status = await backend.loadStatus();
    expect(calls, ['withdrawal_status']);
    expect(status.minimumMinor, 2000);
    expect(status.feeMinor, 250);
    expect(status.contactVerified, isTrue);
    expect(status.netFor(3000), 2750);
    expect(status.requests.single.isFailed, isTrue);
    expect(status.requests.single.failureReason, 'account closed');
  });

  test('an invalid status row is rejected, never defaulted', () async {
    final backend = Phase2WithdrawalBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => _statusJson(
        requests: [
          {
            'id': 'x',
            'amount_minor': -1,
            'fee_minor': 250,
            'net_minor': 2750,
            'status': 'paid',
            'created_at': 'not-a-date',
          },
        ],
      ),
    );
    await expectLater(
      backend.loadStatus(),
      throwsA(isA<WithdrawalUnavailableException>()),
    );
  });

  test('requestWithdrawal sends the client key and amount', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2WithdrawalBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'status': 'processing',
          'withdrawal_id': '80000000-0000-4000-8000-000000000002',
          'amount_minor': 3000,
          'fee_minor': 250,
          'net_minor': 2750,
        };
      },
    );
    final created = await backend.requestWithdrawal(
      amountMinor: 3000,
      operationKey: 'wd-1',
    );
    expect(created.netMinor, 2750);
    expect(calls.single.$1, 'withdrawal_request');
    expect(calls.single.$2['p_key'], 'wd-1');
    expect(calls.single.$2['p_amount_minor'], 3000);
  });

  test('server refusals keep their honest messages', () async {
    Future<WithdrawalBackend> withError(String code, String message) async =>
        Phase2WithdrawalBackend(
          identity: () => 'user-a',
          rpc: (function, params) async =>
              throw WithdrawalRpcException(message, code: code, statusCode: 400),
        );
    await expectLater(
      (await withError('P0001', 'contact_verification_required'))
          .requestWithdrawal(amountMinor: 3000, operationKey: 'k'),
      throwsA(
        isA<WithdrawalUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('Verify your email and phone'),
        ),
      ),
    );
    await expectLater(
      (await withError('P0001', 'insufficient_earned_balance'))
          .requestWithdrawal(amountMinor: 3000, operationKey: 'k'),
      throwsA(
        isA<WithdrawalUnavailableException>().having(
          (e) => e.outcomeUncertain,
          'uncertain',
          isFalse,
        ),
      ),
    );
  });

  test('a session change during dispatch is refused', () async {
    var identity = 'user-a';
    final backend = Phase2WithdrawalBackend(
      identity: () => identity,
      rpc: (function, params) async {
        identity = 'user-b';
        return _statusJson();
      },
    );
    await expectLater(
      backend.loadStatus(),
      throwsA(
        isA<WithdrawalUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('session changed'),
        ),
      ),
    );
  });
}
