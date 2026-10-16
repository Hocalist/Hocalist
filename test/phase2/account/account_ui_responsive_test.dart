// Rendered responsive proof for the new account-completion surfaces at the
// required logical widths and text scales. Widget-rendered (Flutter test
// harness); no browser, SDK, network or provider call.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/trust/trust_backend.dart';
import 'package:hocalist/domain/phase2/account_completion.dart';
import 'package:hocalist/domain/phase2/catalogue.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/account_health_status_card.dart';
import 'package:hocalist/features/account/account_lifecycle_page.dart';
import 'package:hocalist/features/account/account_recovery_pages.dart';
import 'package:hocalist/features/account/account_security_page.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/account/restricted_account_panel.dart';
import 'package:hocalist/features/account/seller_category_editor.dart';

import 'account_test_fakes.dart';

const _widths = [320.0, 360.0, 390.0, 430.0];
const _scales = [1.0, 1.15, 1.3, 1.6];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required double width,
  required double scale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

class _TrustStub implements TrustBackend {
  _TrustStub({this.failLoad = false});

  final bool failLoad;

  @override
  Future<TrustStatusView> loadStatus() async {
    if (failLoad) throw const TrustUnavailableException('offline');
    return TrustStatusView(
      emailVerified: true,
      phoneVerified: false,
      reviewStatus: 'not_submitted',
      items: const [],
      restrictions: [
        AccountRestrictionView(
          id: 'restriction-1',
          scope: 'seller',
          reason: 'Repeated confirmed no-shows after review.',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ],
    );
  }

  @override
  Future<void> submitAppeal({
    required String restrictionId,
    required String body,
    required String operationKey,
  }) async {}

  @override
  Future<VerificationItemView> submitVerification({
    required String kind,
    required String note,
    required String operationKey,
    List<String> evidenceMediaIds = const <String>[],
  }) async => VerificationItemView(
    id: 'verification-1',
    kind: kind,
    status: 'pending',
    evidenceCount: 0,
    createdAt: DateTime.utc(2026, 9, 1),
  );

  @override
  Future<EvidenceMutationView> attachReviewEvidence({
    required String submissionId,
    required List<String> mediaIds,
    required String operationKey,
  }) async => EvidenceMutationView(
    submissionId: submissionId,
    revision: 2,
    mediaIds: mediaIds,
  );

  @override
  Future<EvidenceMutationView> detachReviewEvidence({
    required String submissionId,
    required String mediaId,
    required String operationKey,
  }) async => EvidenceMutationView(
    submissionId: submissionId,
    revision: 3,
    mediaIds: const [],
  );

  @override
  Future<EvidenceMutationView> attachReportEvidence({
    required String caseId,
    required List<String> mediaIds,
    required String operationKey,
  }) async =>
      EvidenceMutationView(caseId: caseId, revision: 1, mediaIds: mediaIds);

  @override
  Future<EvidenceMutationView> detachReportEvidence({
    required String caseId,
    required String mediaId,
    required String operationKey,
  }) async =>
      EvidenceMutationView(caseId: caseId, revision: 2, mediaIds: const []);

  @override
  Future<ReviewEvidencePage> loadReviewEvidence({int limit = 50}) async =>
      const ReviewEvidencePage(items: [], retentionJobsEnabled: false);
}

SellerCategoryOption _option(String id, String label) => SellerCategoryOption(
  id: id,
  label: 'A long catalogue category label $label',
  scope: CatalogueScope.both,
  status: CatalogueEntryStatus.active,
  selectable: true,
  sortOrder: 0,
);

void main() {
  for (final width in _widths) {
    for (final scale in _scales) {
      testWidgets('recovery pages fit $width at $scale', (tester) async {
        await _pump(
          tester,
          AccountRecoveryRequestPage(onSubmit: (_) async {}, onBack: () {}),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          AccountRecoveryPasswordPage(
            onSubmit: (_) async {},
            onCancel: () async {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('recovery status pages fit $width at $scale', (tester) async {
        await _pump(
          tester,
          AccountRecoveryEmailSentPage(
            email: 'a@example.invalid',
            onBack: () {},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          AccountRecoveryLinkExpiredPage(expired: true, onBack: () {}),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('category editor populated state fits $width at $scale', (
        tester,
      ) async {
        await _pump(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: SellerCategoryEditor(
                load: () async => SellerCategorySelection(
                  membershipId: 'membership-seller',
                  revision: 3,
                  selected: [_option('cat-1', 'one')],
                  available: [
                    _option('cat-1', 'one'),
                    _option('cat-2', 'two'),
                    _option('cat-3', 'three'),
                  ],
                ),
                save: (revision, ids) async => SellerCategoryUpdateResult(
                  membershipId: 'membership-seller',
                  revision: revision + 1,
                  categoryIds: ids,
                ),
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('sellerCategoryEditor')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('category editor empty state fits $width at $scale', (
        tester,
      ) async {
        await _pump(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: SellerCategoryEditor(
                load: () async => SellerCategorySelection(
                  membershipId: 'membership-seller',
                  revision: 1,
                  selected: const [],
                  available: const [],
                ),
                save: (revision, ids) async => SellerCategoryUpdateResult(
                  membershipId: 'membership-seller',
                  revision: revision + 1,
                  categoryIds: ids,
                ),
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('sellerCategoryEmpty')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('restricted appeal surface fits $width at $scale', (
        tester,
      ) async {
        final auth = FakeAuthGateway();
        addTearDown(auth.dispose);
        final accounts = FakeAccountRepository();
        accounts.membershipHandler = (_) =>
            RepositorySuccess(membership(status: MembershipStatus.restricted));
        final controller = HocalistAccountController(
          auth: auth,
          accounts: accounts,
        );
        addTearDown(controller.dispose);
        auth.signIn(
          const AuthIdentitySnapshot(
            userId: 'user-a',
            email: 'a@example.invalid',
          ),
        );
        await controller.start();
        await _pump(
          tester,
          RestrictedAccountPanel(controller: controller, backend: _TrustStub()),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('restricted-account-panel')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('restricted status failure stays honest at $width/$scale', (
        tester,
      ) async {
        final auth = FakeAuthGateway();
        addTearDown(auth.dispose);
        final accounts = FakeAccountRepository();
        accounts.membershipHandler = (_) =>
            RepositorySuccess(membership(status: MembershipStatus.restricted));
        final controller = HocalistAccountController(
          auth: auth,
          accounts: accounts,
        );
        addTearDown(controller.dispose);
        auth.signIn(
          const AuthIdentitySnapshot(
            userId: 'user-a',
            email: 'a@example.invalid',
          ),
        );
        await controller.start();
        await _pump(
          tester,
          RestrictedAccountPanel(
            controller: controller,
            backend: _TrustStub(failLoad: true),
          ),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('restricted-status-error')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('health projection card fits $width at $scale', (
        tester,
      ) async {
        const projection = AccountHealthProjection(
          emailVerified: true,
          phoneVerified: true,
          reviewStatus: 'approved',
          reviewKind: 'business',
          pendingReview: false,
          activeRestrictions: [],
          retentionJobsEnabled: false,
        );
        await _pump(
          tester,
          const Scaffold(
            body: Center(
              child: AccountHealthStatusCard(projection: projection),
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('security and lifecycle pages fit $width at $scale', (
        tester,
      ) async {
        final auth = FakeAuthGateway();
        addTearDown(auth.dispose);
        final accounts = FakeAccountRepository();
        final controller = HocalistAccountController(
          auth: auth,
          accounts: accounts,
        );
        addTearDown(controller.dispose);
        auth.signIn(
          const AuthIdentitySnapshot(
            userId: 'user-a',
            email: 'a@example.invalid',
          ),
        );
        await controller.start();
        await _pump(
          tester,
          AccountSecurityPage(controller: controller, onBack: () {}),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('security-current-email')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          AccountLifecyclePage(onBack: () {}),
          width: width,
          scale: scale,
        );
        expect(
          find.byKey(const ValueKey('lifecycle-unavailable')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
