// Trust backend tests: reviewed evidence, restriction and appeal mapping plus
// the session fence. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/trust/trust_backend.dart';

Map<String, Object?> _verificationJson({List<Map<String, Object?>>? items}) => {
  'email_phone': {'email_verified': true, 'phone_verified': false},
  'items': items ?? const [],
};

Map<String, Object?> _healthJson({
  String reviewStatus = 'not_submitted',
  List<Map<String, Object?>>? restrictions,
}) => {
  'verified_email_phone': {'email_verified': true, 'phone_verified': false},
  'review_status': reviewStatus,
  'restrictions': restrictions ?? const [],
  'reports_are_signals_only': true,
};

void main() {
  for (final valid in [true, false]) {
    test(
      'saved evidence references are strictly decoded (valid=$valid)',
      () async {
        final backend = Phase2TrustBackend(
          identity: () => 'user-a',
          rpc: (function, params) async {
            if (function == 'verification_status') {
              return _verificationJson(
                items: [
                  {
                    'id': 'review',
                    'kind': 'business',
                    'status': 'pending',
                    'created_at': '2026-10-03T00:00:00Z',
                    'evidence_count': 1,
                    'evidence_media_ids': [
                      valid
                          ? '80000000-0000-4000-8000-000000000001'
                          : 'not-an-id',
                    ],
                  },
                ],
              );
            }
            return _healthJson(reviewStatus: 'pending');
          },
        );
        if (valid) {
          expect((await backend.loadStatus()).items.single.evidenceMediaIds, [
            '80000000-0000-4000-8000-000000000001',
          ]);
        } else {
          await expectLater(
            backend.loadStatus(),
            throwsA(isA<TrustUnavailableException>()),
          );
        }
      },
    );
  }
  for (final readable in [true, false]) {
    test(
      'minimal committed acknowledgement reconciles by id (readable=$readable)',
      () async {
        final backend = Phase2TrustBackend(
          identity: () => 'user-a',
          rpc: (function, params) async {
            if (function == 'verification_submit') {
              return {
                'id': 'submitted-id',
                'kind': 'business',
                'status': 'pending',
                'revision': 1,
              };
            }
            if (function == 'verification_status') {
              return _verificationJson(
                items: readable
                    ? [
                        {
                          'id': 'submitted-id',
                          'kind': 'business',
                          'status': 'pending',
                          'created_at': '2026-10-03T00:00:00Z',
                          'evidence_count': 0,
                        },
                      ]
                    : [],
              );
            }
            return _healthJson(reviewStatus: 'pending');
          },
        );
        final result = backend.submitVerification(
          kind: 'business',
          note: 'Synthetic test only',
          operationKey: 'same-intent',
        );
        if (readable) {
          expect((await result).id, 'submitted-id');
        } else {
          await expectLater(
            result,
            throwsA(
              isA<TrustUnavailableException>().having(
                (e) => e.outcomeUncertain,
                'uncertain',
                true,
              ),
            ),
          );
        }
      },
    );
  }
  test(
    'loadStatus combines verified contacts, review and restrictions',
    () async {
      final backend = Phase2TrustBackend(
        identity: () => 'user-a',
        rpc: (function, params) async {
          if (function == 'verification_status') {
            return _verificationJson(
              items: [
                {
                  'id': '90000000-0000-4000-8000-000000000001',
                  'kind': 'business',
                  'status': 'approved',
                  'note': 'Licence attached',
                  'evidence_count': 0,
                  'decision_reason': 'Matches public records',
                  'created_at': '2026-05-01T00:00:00+00:00',
                },
              ],
            );
          }
          return _healthJson(
            reviewStatus: 'approved',
            restrictions: [
              {
                'id': '91000000-0000-4000-8000-000000000001',
                'scope': 'seller',
                'reason': 'Repeated no-shows',
                'source': 'health',
                'created_at': '2026-05-02T00:00:00+00:00',
                'appeal_id': null,
                'appeal_status': null,
              },
            ],
          );
        },
      );
      final status = await backend.loadStatus();
      expect(status.emailVerified, isTrue);
      expect(status.phoneVerified, isFalse);
      expect(status.reviewStatus, 'approved');
      expect(status.items.single.decisionReason, 'Matches public records');
      expect(status.restrictions.single.canAppeal, isTrue);
    },
  );

  test('submitVerification sends the reviewed payload', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'id': '90000000-0000-4000-8000-000000000002',
          'kind': 'identity',
          'status': 'pending',
          'revision': 1,
          'created_at': '2026-05-03T00:00:00+00:00',
        };
      },
    );
    final item = await backend.submitVerification(
      kind: 'identity',
      note: 'Government identity evidence for review.',
      operationKey: 'ver-1',
    );
    expect(item.status, 'pending');
    expect(calls.single.$1, 'verification_submit');
    expect(calls.single.$2['p_key'], 'ver-1');
    final input = calls.single.$2['p_input']! as Map<String, Object?>;
    expect(input['kind'], 'identity');
    expect(input['evidence_media_ids'], isEmpty);
  });

  test('a pending review maps to an honest refusal', () async {
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => throw const TrustRpcException(
        'verification_pending',
        code: 'P0001',
        statusCode: 400,
      ),
    );
    await expectLater(
      backend.submitVerification(
        kind: 'business',
        note: 'Another submission for review.',
        operationKey: 'ver-2',
      ),
      throwsA(
        isA<TrustUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('already pending'),
        ),
      ),
    );
  });

  test('an appeal sends the restriction and body', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'id': '92000000-0000-4000-8000-000000000001',
          'status': 'submitted',
          'revision': 1,
          'restriction_id': '91000000-0000-4000-8000-000000000001',
        };
      },
    );
    await backend.submitAppeal(
      restrictionId: '91000000-0000-4000-8000-000000000001',
      body: 'The buyer cancelled both appointments.',
      operationKey: 'appeal-1',
    );
    expect(calls.single.$1, 'restriction_appeal_submit');
    final input = calls.single.$2['p_input']! as Map<String, Object?>;
    expect(input['restriction_id'], '91000000-0000-4000-8000-000000000001');
  });

  test('a session change during dispatch is refused', () async {
    var identity = 'user-a';
    final backend = Phase2TrustBackend(
      identity: () => identity,
      rpc: (function, params) async {
        identity = 'user-b';
        return _verificationJson();
      },
    );
    await expectLater(
      backend.loadStatus(),
      throwsA(
        isA<TrustUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('session changed'),
        ),
      ),
    );
  });

  test('submitVerification forwards the selected evidence ids', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'id': '90000000-0000-4000-8000-000000000003',
          'kind': 'business',
          'status': 'pending',
          'revision': 1,
          'created_at': '2026-05-04T00:00:00+00:00',
        };
      },
    );
    await backend.submitVerification(
      kind: 'business',
      note: 'Licence and storefront for review.',
      operationKey: 'ver-3',
      evidenceMediaIds: const ['80000000-0000-4000-8000-000000000001'],
    );
    final input = calls.single.$2['p_input']! as Map<String, Object?>;
    expect(input['evidence_media_ids'], [
      '80000000-0000-4000-8000-000000000001',
    ]);
  });

  test('review evidence attach and detach send stable keys', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async {
        calls.add((function, params));
        return {
          'submission_id': '90000000-0000-4000-8000-000000000004',
          'revision': 3,
          'evidence_media_ids': ['80000000-0000-4000-8000-000000000001'],
        };
      },
    );
    final attached = await backend.attachReviewEvidence(
      submissionId: '90000000-0000-4000-8000-000000000004',
      mediaIds: const ['80000000-0000-4000-8000-000000000001'],
      operationKey: 'evidence-1',
    );
    expect(attached.revision, 3);
    expect(attached.mediaIds, hasLength(1));
    final detached = await backend.detachReviewEvidence(
      submissionId: '90000000-0000-4000-8000-000000000004',
      mediaId: '80000000-0000-4000-8000-000000000001',
      operationKey: 'evidence-2',
    );
    expect(detached.revision, 3);
    expect(calls.map((call) => call.$1), [
      'review_evidence_attach',
      'review_evidence_detach',
    ]);
    expect(calls.first.$2['p_key'], 'evidence-1');
  });

  test('cross-user evidence rejection maps to an honest refusal', () async {
    final backend = Phase2TrustBackend(
      identity: () => 'user-a',
      rpc: (function, params) async => throw const TrustRpcException(
        'invalid_evidence_reference',
        code: '22023',
        statusCode: 400,
      ),
    );
    await expectLater(
      backend.attachReviewEvidence(
        submissionId: '90000000-0000-4000-8000-000000000004',
        mediaIds: const ['80000000-0000-4000-8000-000000000002'],
        operationKey: 'evidence-3',
      ),
      throwsA(
        isA<TrustUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('your own ready review evidence'),
        ),
      ),
    );
  });

  test('admin evidence page carries the read contract facts', () async {
    final backend = Phase2TrustBackend(
      identity: () => 'admin-user',
      rpc: (function, params) async {
        expect(function, 'admin_review_evidence');
        return {
          'read_contract': {
            'edge_function': 'hocalist-media',
            'action': 'read',
            'media_id_parameter': 'id',
          },
          'retention_jobs_enabled': false,
          'items': [
            {
              'media_id': '80000000-0000-4000-8000-000000000001',
              'purpose': 'review',
              'state': 'ready',
              'size_bytes': 1024,
              'width': 40,
              'height': 40,
              'created_at': '2026-05-05T00:00:00+00:00',
              'owner_user_id': 'user-a',
              'owner_name': 'Synthetic Seller',
              'submission_id': '90000000-0000-4000-8000-000000000004',
              'submission_kind': 'business',
              'submission_status': 'pending',
              'case_id': null,
              'case_reason': null,
              'case_status': null,
              'held': true,
            },
          ],
        };
      },
    );
    final page = await backend.loadReviewEvidence(limit: 10);
    expect(page.retentionJobsEnabled, isFalse);
    expect(page.items.single.purpose, 'review');
    expect(page.items.single.held, isTrue);
    expect(page.items.single.ownerName, 'Synthetic Seller');
    expect(ReviewEvidencePage.edgeFunction, 'hocalist-media');
    expect(ReviewEvidencePage.readAction, 'read');
    expect(ReviewEvidencePage.mediaIdParameter, 'id');
  });
}
