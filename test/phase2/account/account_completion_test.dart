// Account completion UI and backend-boundary tests: seller category editing,
// consent/export/deletion request, restricted appeal and the health
// projection. Fakes only: no SDK, network, database or provider call.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/accounts/account_lifecycle_backend.dart';
import 'package:hocalist/data/phase2/accounts/profile_categories_backend.dart';
import 'package:hocalist/data/phase2/trust/trust_backend.dart';
import 'package:hocalist/domain/phase2/account_completion.dart';
import 'package:hocalist/domain/phase2/catalogue.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/account_health_status_card.dart';
import 'package:hocalist/features/account/account_lifecycle_page.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/account/restricted_account_panel.dart';
import 'package:hocalist/features/account/seller_category_editor.dart';
import 'package:hocalist/theme/buyer_ui_foundation.dart';

import 'account_test_fakes.dart';

SellerCategoryOption option(
  String id,
  String label, {
  CatalogueEntryStatus status = CatalogueEntryStatus.active,
  bool selectable = true,
}) => SellerCategoryOption(
  id: id,
  label: label,
  scope: CatalogueScope.both,
  status: status,
  selectable: selectable,
  sortOrder: 0,
);

class FakeProfileCategoriesBackend implements ProfileCategoriesBackend {
  SellerCategorySelection selection = SellerCategorySelection(
    membershipId: 'membership-seller',
    revision: 3,
    selected: [option('cat-1', 'Electronics')],
    available: [option('cat-1', 'Electronics'), option('cat-2', 'Furniture')],
  );
  Object? loadError;
  Object? updateError;
  int loadCalls = 0;
  final List<List<String>> updates = <List<String>>[];

  @override
  Future<SellerCategorySelection> loadSellerCategories() async {
    loadCalls += 1;
    if (loadError != null) throw loadError!;
    return selection;
  }

  @override
  Future<SellerCategoryUpdateResult> updateSellerCategories({
    required int expectedRevision,
    required List<String> categoryIds,
    required String operationKey,
  }) async {
    if (updateError != null) throw updateError!;
    updates.add(List<String>.from(categoryIds));
    return SellerCategoryUpdateResult(
      membershipId: selection.membershipId,
      revision: expectedRevision + 1,
      categoryIds: categoryIds,
    );
  }
}

class FakeTrustBackend implements TrustBackend {
  TrustStatusView status = TrustStatusView(
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
  bool appealCalled = false;

  @override
  Future<TrustStatusView> loadStatus() async => status;

  @override
  Future<void> submitAppeal({
    required String restrictionId,
    required String body,
    required String operationKey,
  }) async {
    appealCalled = true;
  }

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
    evidenceCount: evidenceMediaIds.length,
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
    mediaIds: const <String>[],
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
  }) async => EvidenceMutationView(
    caseId: caseId,
    revision: 2,
    mediaIds: const <String>[],
  );

  @override
  Future<ReviewEvidencePage> loadReviewEvidence({int limit = 50}) async =>
      const ReviewEvidencePage(items: [], retentionJobsEnabled: false);
}

class FakeLifecycleBackend implements AccountLifecycleBackend {
  AccountLifecycleStatusView status = const AccountLifecycleStatusView(
    documents: [
      ConsentDocumentView(
        id: 'terms',
        version: '2026-09',
        label: 'Terms of service',
        isRequired: true,
        sortOrder: 0,
        revision: 1,
      ),
    ],
    acceptedConsents: [],
  );
  Object? requestError;
  int exportRequests = 0;
  int deletionRequests = 0;
  int cancels = 0;

  @override
  Future<AccountLifecycleStatusView> loadStatus() async => status;

  @override
  Future<ConsentRecordView> recordConsent({
    required String documentId,
    required String version,
    required String operationKey,
  }) async {
    if (requestError != null) throw requestError!;
    final record = ConsentRecordView(
      documentId: documentId,
      version: version,
      acceptedAt: DateTime.utc(2026, 9, 26),
    );
    status = AccountLifecycleStatusView(
      documents: status.documents,
      acceptedConsents: [record],
    );
    return record;
  }

  @override
  Future<AccountExportView> requestExport({
    required String operationKey,
  }) async {
    if (requestError != null) throw requestError!;
    exportRequests += 1;
    final export = AccountExportView(
      requestId: 'export-1',
      status: 'ready',
      requestedAt: DateTime.utc(2026, 9, 26),
      readyAt: DateTime.utc(2026, 9, 26),
      revision: 2,
    );
    status = AccountLifecycleStatusView(
      documents: status.documents,
      acceptedConsents: status.acceptedConsents,
      latestExport: export,
    );
    return export;
  }

  @override
  Future<AccountExportDocument> readExport({required String requestId}) async {
    if (requestError != null) throw requestError!;
    return AccountExportDocument(
      requestId: requestId,
      generatedAt: DateTime.utc(2026, 9, 26),
      payload: const {'schema_scope': 'hocalist'},
    );
  }

  @override
  Future<AccountDeletionView> requestDeletion({
    required String operationKey,
  }) async {
    if (requestError != null) throw requestError!;
    deletionRequests += 1;
    final deletion = AccountDeletionView(
      requestId: 'deletion-1',
      status: 'blocked',
      scope: 'hocalist',
      holds: const [DeletionHoldView(kind: 'withdrawal_processing')],
      requestedAt: DateTime.utc(2026, 9, 26),
      revision: 1,
      cancelable: true,
    );
    status = AccountLifecycleStatusView(
      documents: status.documents,
      acceptedConsents: status.acceptedConsents,
      latestExport: status.latestExport,
      openDeletion: deletion,
    );
    return deletion;
  }

  @override
  Future<AccountDeletionView> cancelDeletion({
    required String requestId,
    required int expectedRevision,
    String? reason,
    required String operationKey,
  }) async {
    if (requestError != null) throw requestError!;
    cancels += 1;
    status = AccountLifecycleStatusView(
      documents: status.documents,
      acceptedConsents: status.acceptedConsents,
      latestExport: status.latestExport,
    );
    return AccountDeletionView(
      requestId: requestId,
      status: 'cancelled',
      scope: 'hocalist',
      holds: const [],
      requestedAt: DateTime.utc(2026, 9, 26),
      revision: expectedRevision + 1,
      cancelable: false,
    );
  }
}

void main() {
  testWidgets(
    'category editor uses catalogue options and saves the selection',
    (tester) async {
      final backend = FakeProfileCategoriesBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerCategoryEditor(
              load: backend.loadSellerCategories,
              save: (revision, ids) => backend.updateSellerCategories(
                expectedRevision: revision,
                categoryIds: ids,
                operationKey: 'key',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sellerCategory-cat-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sellerCategory-cat-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sellerCategorySave')));
      await tester.pumpAndSettle();

      expect(backend.updates, [
        ['cat-1', 'cat-2'],
      ]);
    },
  );

  testWidgets('retired selected categories stay visible with a notice', (
    tester,
  ) async {
    final backend = FakeProfileCategoriesBackend();
    backend.selection = SellerCategorySelection(
      membershipId: 'membership-seller',
      revision: 4,
      selected: [
        option(
          'cat-old',
          'Legacy electronics',
          status: CatalogueEntryStatus.retired,
          selectable: false,
        ),
      ],
      available: [option('cat-1', 'Electronics')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerCategoryEditor(
            load: backend.loadSellerCategories,
            save: (revision, ids) => backend.updateSellerCategories(
              expectedRevision: revision,
              categoryIds: ids,
              operationKey: 'key',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sellerCategoryRetiredNotice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sellerCategory-retired-cat-old')),
      findsOneWidget,
    );
  });

  testWidgets('a stale revision reloads and asks for an explicit retry', (
    tester,
  ) async {
    final backend = FakeProfileCategoriesBackend();
    backend.updateError = const ProfileCategoriesConflictException();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerCategoryEditor(
            load: backend.loadSellerCategories,
            save: (revision, ids) => backend.updateSellerCategories(
              expectedRevision: revision,
              categoryIds: ids,
              operationKey: 'key',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sellerCategorySave')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sellerCategoryError')), findsOneWidget);
    expect(backend.loadCalls, greaterThan(1));
  });

  testWidgets('the filter shows a filtered-empty state', (tester) async {
    final backend = FakeProfileCategoriesBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerCategoryEditor(
            load: backend.loadSellerCategories,
            save: (revision, ids) => backend.updateSellerCategories(
              expectedRevision: revision,
              categoryIds: ids,
              operationKey: 'key',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sellerCategoryFilter')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sellerCategoryFilteredEmpty')),
      findsOneWidget,
    );
  });

  testWidgets('lifecycle page records consent, export and deletion request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeLifecycleBackend();
    final passwords = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLifecyclePage(
          backend: backend,
          email: 'a@example.invalid',
          reauthenticate: (password) async => passwords.add(password),
          onBack: () {},
          newOperationKey: () => 'key',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lifecycle-accept-terms')));
    await tester.pumpAndSettle();
    expect(backend.status.acceptedConsents, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('lifecycle-export-request')));
    await tester.pumpAndSettle();
    expect(backend.exportRequests, 1);

    await tester.enterText(
      find.byKey(const ValueKey('lifecycle-delete-password')),
      'old-password',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('lifecycle-delete-request')),
    );
    await tester.tap(find.byKey(const ValueKey('lifecycle-delete-request')));
    await tester.pumpAndSettle();

    expect(passwords, ['old-password']);
    expect(backend.deletionRequests, 1);
    expect(
      find.byKey(const ValueKey('lifecycle-deletion-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lifecycle-hold-withdrawal_processing')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('lifecycle-delete-cancel')),
    );
    await tester.tap(find.byKey(const ValueKey('lifecycle-delete-cancel')));
    await tester.pumpAndSettle();
    expect(backend.cancels, 1);
  });

  testWidgets('lifecycle deletion stays disabled without reauthentication', (
    tester,
  ) async {
    final backend = FakeLifecycleBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountLifecyclePage(backend: backend, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<BuyerPrimaryButton>(
      find.byKey(const ValueKey('lifecycle-delete-request')),
    );
    expect(button.onPressed, isNull);
    expect(backend.deletionRequests, 0);
  });

  testWidgets(
    'a session change during confirmation blocks the deletion request',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeLifecycleBackend();
      var sessionCurrent = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountLifecyclePage(
            backend: backend,
            reauthenticate: (_) async => sessionCurrent = false,
            isSessionCurrent: () => sessionCurrent,
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('lifecycle-delete-password')),
        'old-password',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lifecycle-delete-request')));
      await tester.pumpAndSettle();

      expect(backend.deletionRequests, 0);
      expect(
        find.byKey(const ValueKey('lifecycle-delete-error')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a restricted user sees status and can submit one appeal', (
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
      newIdempotencyKey: () => 'key',
    );
    addTearDown(controller.dispose);
    auth.signIn(
      const AuthIdentitySnapshot(userId: 'user-a', email: 'a@example.invalid'),
    );
    await controller.start();

    final backend = FakeTrustBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: RestrictedAccountPanel(controller: controller, backend: backend),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('restricted-account-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('seller restriction'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'The buyer cancelled both appointments on the day.',
    );
    await tester.tap(find.byKey(const ValueKey('restricted-appeal-submit')));
    await tester.pumpAndSettle();
    expect(backend.appealCalled, isTrue);
  });

  testWidgets('the health card renders server facts and no invented score', (
    tester,
  ) async {
    const projection = AccountHealthProjection(
      emailVerified: true,
      phoneVerified: false,
      reviewStatus: 'approved',
      reviewKind: 'business',
      pendingReview: false,
      activeRestrictions: [],
      retentionJobsEnabled: false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AccountHealthStatusCard(projection: projection)),
      ),
    );
    expect(find.text('Reviewed evidence approved'), findsOneWidget);
    expect(find.textContaining('No automatic score'), findsOneWidget);
  });
}
