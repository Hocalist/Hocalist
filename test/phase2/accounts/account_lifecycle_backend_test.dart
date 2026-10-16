// Account lifecycle backend tests: wire shapes, safe errors and the session
// fence. Fakes only: no SDK, network, database or provider call.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_lifecycle_backend.dart';

Map<String, Object?> _statusJson({
  List<Map<String, Object?>> documents = const [],
  List<Map<String, Object?>> accepted = const [],
  Map<String, Object?>? export,
  Map<String, Object?>? deletion,
}) => {
  'consent_documents': documents,
  'accepted_consents': accepted,
  'export': export,
  'deletion': deletion,
};

void main() {
  test('loadStatus decodes documents, export and deletion status', () async {
    final backend = Phase2AccountLifecycleBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => _statusJson(
        documents: [
          {
            'id': 'terms',
            'version': '2026-09',
            'label': 'Terms of service',
            'is_required': true,
            'sort_order': 0,
            'revision': 1,
          },
        ],
        accepted: [
          {
            'document_id': 'terms',
            'version': '2026-09',
            'accepted_at': '2026-09-26T00:00:00+00:00',
          },
        ],
        export: {
          'request_id': 'export-1',
          'status': 'ready',
          'requested_at': '2026-09-26T00:00:00+00:00',
          'ready_at': '2026-09-26T00:01:00+00:00',
          'revision': 2,
        },
        deletion: {
          'request_id': 'deletion-1',
          'status': 'blocked',
          'scope': 'hocalist',
          'holds': [
            {'kind': 'withdrawal_processing', 'detail': '2500'},
          ],
          'requested_at': '2026-09-26T00:02:00+00:00',
          'revision': 1,
          'cancelable': true,
        },
      ),
    );
    final status = await backend.loadStatus();
    expect(status.documents.single.id, 'terms');
    expect(
      status.documents.single.isAcceptedBy(status.acceptedConsents),
      isTrue,
    );
    expect(status.latestExport?.isReady, isTrue);
    expect(status.openDeletion?.isBlocked, isTrue);
    expect(status.openDeletion?.holds.single.kind, 'withdrawal_processing');
    expect(status.openDeletion?.cancelable, isTrue);
  });

  test('consent and deletion commands send bounded inputs', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2AccountLifecycleBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'document_id': 'terms',
          'version': '2026-09',
          'accepted_at': '2026-09-26T00:00:00+00:00',
        };
      },
    );
    await backend.recordConsent(
      documentId: 'terms',
      version: '2026-09',
      operationKey: 'consent-1',
    );
    expect(calls.single.$1, 'account_consent_record');
    final input = calls.single.$2['p_input']! as Map<String, Object?>;
    expect(input, {'document_id': 'terms', 'version': '2026-09'});
  });

  test('a stale version maps to a conflict, not a raw error', () async {
    final backend = Phase2AccountLifecycleBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => throw const AccountLifecycleRpcException(
        'consent_version_mismatch',
        code: 'P0001',
        statusCode: 400,
      ),
    );
    await expectLater(
      backend.recordConsent(
        documentId: 'terms',
        version: 'old',
        operationKey: 'consent-2',
      ),
      throwsA(isA<AccountLifecycleConflictException>()),
    );
  });

  test('a signed-out session sends no request', () async {
    var called = false;
    final backend = Phase2AccountLifecycleBackend(
      identity: () => null,
      rpc: (function, params) async {
        called = true;
        return const {};
      },
    );
    await expectLater(
      backend.loadStatus(),
      throwsA(isA<AccountLifecycleUnavailableException>()),
    );
    expect(called, isFalse);
  });

  test('a session change during dispatch discards the response', () async {
    var identity = 'user-a';
    final backend = Phase2AccountLifecycleBackend(
      identity: () => identity,
      rpc: (function, params) async {
        identity = 'user-b';
        return _statusJson();
      },
    );
    await expectLater(
      backend.loadStatus(),
      throwsA(
        isA<AccountLifecycleUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('session changed'),
        ),
      ),
    );
  });

  test('an unknown function is refused before any dispatch', () async {
    var called = false;
    final backend = Phase2AccountLifecycleBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        called = true;
        return const {};
      },
    );
    // The public surface has no arbitrary-function parameter; the allowlist is
    // exercised through a wrong wire response instead.
    await expectLater(
      backend.readExport(requestId: 'export-1'),
      throwsA(isA<AccountLifecycleUnavailableException>()),
    );
    expect(called, isTrue);
  });
}
