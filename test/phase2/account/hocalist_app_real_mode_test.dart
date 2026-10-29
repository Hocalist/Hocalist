// Entry-point regressions for configured real mode. These pump the actual
// HocalistApp without an outer MaterialApp so the application-shell defect
// cannot be hidden by the test harness. No live provider call is made.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/phase2/providers/hocalist_client_config.dart';
import 'package:hocalist/data/phase2/providers/provider_runtime.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';
import 'package:hocalist/features/approved/request_flow_pages.dart';
import 'package:hocalist/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/features/account/real_account_gate.dart';
import 'package:hocalist/data/phase2/trust/trust_backend.dart';

import 'account_test_fakes.dart';

const realConfig = HocalistClientConfig(publishableKey: 'sb_publishable_test');

const signedInA = AuthIdentitySnapshot(
  userId: 'user-a',
  email: 'a@example.invalid',
);

class _AppealBackend implements TrustBackend {
  int appeals = 0;
  @override
  Future<TrustStatusView> loadStatus() async => TrustStatusView(
    emailVerified: true, phoneVerified: false, reviewStatus: 'pending', items: const [],
    restrictions: [AccountRestrictionView(id: 'restriction-test', scope: 'seller',
      reason: 'Synthetic restriction', createdAt: DateTime.utc(2026, 10, 29))],
  );
  @override
  Future<void> submitAppeal({required String restrictionId, required String body, required String operationKey}) async {
    expect(restrictionId, 'restriction-test');
    expect(body, 'Please review this synthetic restriction.');
    appeals++;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAccountServices implements HocalistAccountServices {
  FakeAccountServices({
    required this.accountAuth,
    required this.accounts,
    Future<void> Function()? disablePush,
  }) : disablePush = disablePush ?? _noop;

  @override
  final AccountAuthGateway accountAuth;

  @override
  final AccountRepository accounts;

  @override
  final Future<void> Function() disablePush;

  static Future<void> _noop() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('restricted appeal backend resolves after provider initialization', (tester) async {
    final pending = Completer<HocalistAccountServices>();
    final accounts = FakeAccountRepository();
    accounts.membershipHandler = (_) => RepositorySuccess(membership(status: MembershipStatus.restricted));
    final auth = FakeAuthGateway(identity: signedInA);
    addTearDown(auth.dispose);
    final backend = _AppealBackend();
    var ready = false;
    var resolved = 0;
    await tester.pumpWidget(HocalistRealProviderBootstrap(
      publishableKey: 'sb_publishable_test', initialize: (_) => pending.future,
      shellBuilder: (child) => MaterialApp(home: child),
      activeBuilder: (_, controller) => const Text('UNEXPECTED ACTIVE APP'),
      trustBackendFactory: () { expect(ready, isTrue); resolved++; return backend; },
    ));
    await tester.pump();
    expect(resolved, 0);
    ready = true;
    pending.complete(FakeAccountServices(accountAuth: auth, accounts: accounts));
    await tester.pumpAndSettle();
    expect(resolved, greaterThan(0));
    expect(find.byKey(const ValueKey('restricted-status-unavailable')), findsNothing);
    expect(find.text('UNEXPECTED ACTIVE APP'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Please review this synthetic restriction.');
    final submit = find.byKey(const ValueKey('restricted-appeal-submit'));
    await tester.ensureVisible(submit); await tester.tap(submit); await tester.pumpAndSettle();
    expect(backend.appeals, 1);
    expect(tester.takeException(), isNull);
  });

  for (final sameUser in [true, false]) {
    testWidgets(
      'real reload restores only the same user navigation: $sameUser',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'hocalist.hasSession': true,
          'hocalist.navigation.${sameUser ? 'user-a' : 'other-user'}.buyer':
              'buyerSettings',
        });
        final accounts = FakeAccountRepository();
        accounts.membershipHandler = (_) => RepositorySuccess(membership());
        accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
        final auth = FakeAuthGateway(identity: signedInA);
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          HocalistApp(
            config: realConfig,
            connectionsInitializer: (_) async =>
                FakeAccountServices(accountAuth: auth, accounts: accounts),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Account Settings'),
          sameUser ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('real mode renders a loading shell before initialization', (
    tester,
  ) async {
    final pending = Completer<HocalistAccountServices>();

    await tester.pumpWidget(
      HocalistApp(
        config: realConfig,
        connectionsInitializer: (_) => pending.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('real-account-loading')), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real mode renders an initialization failure shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      HocalistApp(
        config: realConfig,
        connectionsInitializer: (_) async =>
            throw const ProviderOperationException(
              'public_client_key_required',
            ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('real-account-init-failure')),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('could not start'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production initializer receives the named public key', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(const HocalistApp(config: realConfig));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(
      find.byKey(const ValueKey('real-account-init-failure')),
      findsOneWidget,
    );
    expect(find.textContaining('Android and iOS app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signed-out real mode renders the account page with app context',
    (tester) async {
      final services = FakeAccountServices(
        accountAuth: FakeAuthGateway(),
        accounts: FakeAccountRepository(),
      );

      await tester.pumpWidget(
        HocalistApp(
          config: realConfig,
          connectionsInitializer: (_) async => services,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ApprovedAccountCreationPage), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a fresh callback restores the explicitly selected seller role', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'hocalist.auth.selected_role': 'seller',
    });
    final accounts = FakeAccountRepository();
    final auth = FakeAuthGateway(identity: signedInA);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      HocalistApp(
        config: realConfig,
        connectionsInitializer: (_) async =>
            FakeAccountServices(accountAuth: auth, accounts: accounts),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Finish your seller account'), findsOneWidget);
    expect(find.text('Create buyer account'), findsNothing);
    expect(accounts.requestedRoles, [HocalistRole.seller]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active real mode renders one app shell and fresh content', (
    tester,
  ) async {
    final accounts = FakeAccountRepository();
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final services = FakeAccountServices(
      accountAuth: FakeAuthGateway(identity: signedInA),
      accounts: accounts,
    );

    await tester.pumpWidget(
      HocalistApp(
        config: realConfig,
        connectionsInitializer: (_) async => services,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HocalistPrototype), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Good morning'), findsOneWidget);
  });

  testWidgets('unconfigured real entry keeps the prototype mode', (
    tester,
  ) async {
    await tester.pumpWidget(const HocalistApp());

    expect(find.byType(HocalistPrototype), findsOneWidget);
    expect(find.byType(ApprovedAccountCreationPage), findsNothing);
  });

  for (final accountRole in HocalistRole.values) {
    testWidgets(
      '$accountRole security and lifecycle routes have bounded shells',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'hocalist.auth.selected_role': accountRole.name,
        });
        final accounts = FakeAccountRepository();
        accounts.membershipHandler = (_) =>
            RepositorySuccess(membership(role: accountRole));
        accounts.profileHandler = (_) =>
            RepositorySuccess(roleProfile(role: accountRole));
        await tester.pumpWidget(
          HocalistApp(
            config: realConfig,
            connectionsInitializer: (_) async => FakeAccountServices(
              accountAuth: FakeAuthGateway(identity: signedInA),
              accounts: accounts,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic host = tester.state(find.byType(HocalistPrototype));
        host.go(AppPage.accountSecurity);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('security-current-password')),
          findsOneWidget,
        );
        expect(find.byType(AppFrame), findsNothing);
        host.go(AppPage.accountLifecycle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AppFrame), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('new real request has its own empty draft on every new intent', (
    tester,
  ) async {
    final accounts = FakeAccountRepository();
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    await tester.pumpWidget(
      HocalistApp(
        config: realConfig,
        connectionsInitializer: (_) async => FakeAccountServices(
          accountAuth: FakeAuthGateway(identity: signedInA),
          accounts: accounts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Drive the real dashboard callback: selected-request summary fields must
    // never become the new request's title or budget.
    final create = find.text('Post a new request');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    var form = tester.widget<ApprovedRequestFlowPage>(
      find.byType(ApprovedRequestFlowPage),
    );
    expect(form.requestTitle, isEmpty);
    expect(form.budget, isEmpty);
    form.onTitleChanged('Unsaved test draft');
    form.onBudgetChanged(r'$10 - $20');
    await tester.pump();
    form = tester.widget<ApprovedRequestFlowPage>(
      find.byType(ApprovedRequestFlowPage),
    );
    expect(form.requestTitle, 'Unsaved test draft');
    form.onHome!();
    await tester.pumpAndSettle();
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    form = tester.widget<ApprovedRequestFlowPage>(
      find.byType(ApprovedRequestFlowPage),
    );
    expect(form.requestTitle, isEmpty);
    expect(form.budget, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('logout failure on the pending gate shows an inline error', (
    tester,
  ) async {
    await expectLogoutFailureOnGate(
      tester,
      membershipResult: RepositorySuccess(
        membership(status: MembershipStatus.pending),
      ),
      expectedGateKey: 'real-account-membership-pending',
    );
  });

  testWidgets('logout failure on the restricted gate shows an inline error', (
    tester,
  ) async {
    await expectLogoutFailureOnGate(
      tester,
      membershipResult: RepositorySuccess(
        membership(status: MembershipStatus.restricted),
      ),
      expectedGateKey: 'real-account-membership-restricted',
    );
  });

  testWidgets('logout failure on the failed gate shows an inline error', (
    tester,
  ) async {
    await expectLogoutFailureOnGate(
      tester,
      membershipResult: const RepositoryFailureResult(
        ServerError(operation: 'select'),
      ),
      expectedGateKey: 'real-account-failed',
    );
  });
}

/// Pumps the real HocalistApp (no outer MaterialApp) into [expectedGateKey],
/// then fails the local sign-out and asserts the readable inline error, no
/// Flutter exception and no leaked app content.
Future<void> expectLogoutFailureOnGate(
  WidgetTester tester, {
  required RepositoryResult<MembershipRecord> membershipResult,
  required String expectedGateKey,
}) async {
  final auth = FakeAuthGateway(identity: signedInA);
  final accounts = FakeAccountRepository();
  accounts.membershipHandler = (_) => membershipResult;
  final services = FakeAccountServices(accountAuth: auth, accounts: accounts);

  await tester.pumpWidget(
    HocalistApp(
      config: realConfig,
      connectionsInitializer: (_) async => services,
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byKey(ValueKey(expectedGateKey)), findsOneWidget);
  expect(find.byType(HocalistPrototype), findsNothing);

  auth.failLogoutWithoutSignOut = true;
  final logoutButton = find.text('Log out');
  await tester.ensureVisible(logoutButton);
  await tester.tap(logoutButton);
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('real-account-gate-error')), findsOneWidget);
  expect(find.text('Could not sign out. Try again.'), findsOneWidget);
  expect(find.byKey(ValueKey(expectedGateKey)), findsOneWidget);
  expect(find.byType(HocalistPrototype), findsNothing);
  expect(tester.takeException(), isNull);
}
