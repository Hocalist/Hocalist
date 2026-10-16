// Verification review panel tests: pending state, restriction appeal route and
// honest reviewed-evidence labels. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/trust/trust_backend.dart';
import 'package:hocalist/features/account/verification_review_panel.dart';
import 'package:hocalist/features/media/private_image_picker.dart';

import 'test_fonts.dart';

TrustStatusView _status({
  String reviewStatus = 'pending',
  List<VerificationItemView> items = const [],
  List<AccountRestrictionView> restrictions = const [],
}) => TrustStatusView(
  emailVerified: true,
  phoneVerified: false,
  reviewStatus: reviewStatus,
  items: items,
  restrictions: restrictions,
);

Future<void> _pump(
  WidgetTester tester, {
  required TrustStatusView status,
  Future<VerificationItemView> Function(String, String, String)? submit,
  Future<void> Function(String, String, String)? appeal,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VerificationReviewPanel(
            load: () async => status,
            submit:
                submit ?? (kind, note, key) async => throw StateError('unused'),
            appeal: appeal ?? (id, body, key) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      testWidgets('saved evidence controls fit $width / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const media = '80000000-0000-4000-8000-000000000001';
        final item = VerificationItemView(
          id: 'fit-review',
          kind: 'business',
          status: 'pending',
          evidenceCount: 1,
          evidenceMediaIds: [media],
          createdAt: DateTime.utc(2026),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: VerificationReviewPanel(
                    load: () async => _status(items: [item]),
                    submit: (_, _, _) async => item,
                    appeal: (_, _, _) async {},
                    readEvidence: (_) async =>
                        throw StateError('synthetic read outage'),
                    detachEvidence: (_, _, _) async =>
                        const EvidenceMutationView(revision: 2, mediaIds: []),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 saved evidence photo'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('detachEvidence-$media')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'saved evidence removal uses server ids and retries the same intent',
    (tester) async {
      const mediaId = '80000000-0000-4000-8000-000000000001';
      var removed = false;
      final keys = <String>[];
      VerificationItemView item() => VerificationItemView(
        id: 'saved-review',
        kind: 'business',
        status: 'pending',
        evidenceCount: removed ? 0 : 1,
        evidenceMediaIds: removed ? [] : [mediaId],
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationReviewPanel(
                load: () async => _status(items: [item()]),
                submit: (_, _, _) async => item(),
                appeal: (_, _, _) async {},
                readEvidence: (_) async =>
                    throw StateError('synthetic read outage'),
                detachEvidence: (review, media, key) async {
                  expect(review, 'saved-review');
                  expect(media, mediaId);
                  keys.add(key);
                  if (keys.length == 1) {
                    throw const TrustUnavailableException(
                      'Removal pending, retry.',
                      outcomeUncertain: true,
                    );
                  }
                  removed = true;
                  return const EvidenceMutationView(revision: 3, mediaIds: []);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(const Key('detachEvidence-$mediaId'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verificationSubmitError')), findsOneWidget);
      expect(find.text('Retry removal'), findsOneWidget);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(keys[1], keys[0]);
      expect(find.text('0 saved evidence photos'), findsOneWidget);
      expect(remove, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'attachment retry freezes photos and clears the picker on acknowledgement',
    (tester) async {
      final item = VerificationItemView(
        id: 'review-test',
        kind: 'business',
        status: 'pending',
        evidenceCount: 1,
        createdAt: DateTime.utc(2026),
      );
      final attempts = <(List<String>, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerificationReviewPanel(
                load: () async => _status(items: [item]),
                submit: (_, _, _) async => item,
                appeal: (_, _, _) async {},
                evidenceUpload: (_, _) async => 'photo-test',
                attachEvidence: (_, ids, key) async {
                  attempts.add((List.of(ids), key));
                  if (attempts.length == 1) {
                    throw const TrustUnavailableException(
                      'Retry attachment',
                      outcomeUncertain: true,
                    );
                  }
                  return EvidenceMutationView(revision: 2, mediaIds: ids);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 saved evidence photo'), findsOneWidget);
      final first = tester.widget<PrivateImagePicker>(
        find.byType(PrivateImagePicker),
      );
      first.onChanged(['photo-test']);
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('verificationEvidenceAttach')),
      );
      await tester.tap(find.byKey(const Key('verificationEvidenceAttach')));
      await tester.pumpAndSettle();
      final pending = tester.widget<PrivateImagePicker>(
        find.byType(PrivateImagePicker),
      );
      expect(pending.enabled, isFalse);
      expect(find.byKey(const Key('verificationSubmitError')), findsOneWidget);
      pending.onChanged(['different-photo']);
      await tester.tap(find.byKey(const Key('verificationEvidenceAttach')));
      await tester.pumpAndSettle();
      expect(attempts, hasLength(2));
      expect(attempts[1].$1, ['photo-test']);
      expect(attempts[1].$2, attempts[0].$2);
      expect(
        tester.widget<PrivateImagePicker>(find.byType(PrivateImagePicker)).key,
        isNot(first.key),
      );
      expect(find.byKey(const Key('verificationEvidenceAttach')), findsNothing);
    },
  );

  testWidgets('reviewed evidence is separate from email and phone', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _status(
        reviewStatus: 'approved',
        items: [
          VerificationItemView(
            id: '90000000-0000-4000-8000-000000000001',
            kind: 'business',
            status: 'approved',
            evidenceCount: 0,
            decisionReason: 'Matches public records',
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ],
      ),
    );
    expect(find.text('Evidence review approved'), findsOneWidget);
    expect(
      find.text('Email verified: yes · Phone verified: no'),
      findsOneWidget,
    );
    expect(find.textContaining('Matches public records'), findsOneWidget);
    expect(find.byKey(const Key('verificationSubmit')), findsOneWidget);
  });

  testWidgets('a pending review hides the submission form', (tester) async {
    await _pump(
      tester,
      status: _status(
        items: [
          VerificationItemView(
            id: '90000000-0000-4000-8000-000000000002',
            kind: 'identity',
            status: 'pending',
            evidenceCount: 0,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ],
      ),
    );
    expect(find.byKey(const Key('verificationPendingNotice')), findsOneWidget);
    expect(find.byKey(const Key('verificationSubmit')), findsNothing);
  });

  testWidgets('a restriction exposes one appeal route', (tester) async {
    final appeals = <(String, String)>[];
    await _pump(
      tester,
      status: _status(
        restrictions: [
          AccountRestrictionView(
            id: '91000000-0000-4000-8000-000000000001',
            scope: 'seller',
            reason: 'Repeated no-shows',
            createdAt: DateTime.utc(2026, 5, 2),
          ),
        ],
      ),
      appeal: (id, body, key) async => appeals.add((id, body)),
    );
    expect(
      find.byKey(const Key('restriction-91000000-0000-4000-8000-000000000001')),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Appeal note'),
      'The buyer cancelled both appointments.',
    );
    await tester.tap(
      find.byKey(const Key('appeal-91000000-0000-4000-8000-000000000001')),
    );
    await tester.pumpAndSettle();
    expect(appeals, hasLength(1));
    expect(appeals.single.$1, '91000000-0000-4000-8000-000000000001');
  });

  testWidgets('a recorded appeal replaces the form with its status', (
    tester,
  ) async {
    await _pump(
      tester,
      status: _status(
        restrictions: [
          AccountRestrictionView(
            id: '91000000-0000-4000-8000-000000000002',
            scope: 'all',
            reason: 'Review required',
            createdAt: DateTime.utc(2026, 5, 2),
            appealId: '92000000-0000-4000-8000-000000000001',
            appealStatus: 'submitted',
          ),
        ],
      ),
    );
    expect(
      find.byKey(const Key('appeal-91000000-0000-4000-8000-000000000002')),
      findsNothing,
    );
    expect(
      find.byKey(
        const Key('appealStatus-91000000-0000-4000-8000-000000000002'),
      ),
      findsOneWidget,
    );
  });
}
