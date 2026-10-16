// Widget tests for the real account gate phases. Fakes only; the gate must
// never render app content for missing, pending, restricted or failed states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/account/real_account_gate.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

import 'account_test_fakes.dart';

const signedInA = AuthIdentitySnapshot(
  userId: 'user-a',
  email: 'a@example.invalid',
);

Widget gate(HocalistAccountController controller) => MaterialApp(
  home: HocalistRealAccountGate(
    controller: controller,
    activeBuilder: (_, controller) =>
        Scaffold(body: Text('ACTIVE APP ${controller.userId}')),
  ),
);

void main() {
  late FakeAuthGateway auth;
  late FakeAccountRepository accounts;

  setUp(() {
    auth = FakeAuthGateway();
    accounts = FakeAccountRepository();
  });

  tearDown(() async {
    await auth.dispose();
  });

  HocalistAccountController buildController() {
    final controller = HocalistAccountController(
      auth: auth,
      accounts: accounts,
      newIdempotencyKey: () => 'key',
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('signed out shows the approved account creation page', (
    tester,
  ) async {
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));

    expect(find.byType(ApprovedAccountCreationPage), findsOneWidget);
    expect(find.textContaining('ACTIVE APP'), findsNothing);
    for (final provider in ['Continue with Apple', 'Continue with Facebook']) {
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, provider),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('recovery Back to log in restores login instead of signup', (
    tester,
  ) async {
    final controller = buildController();
    await controller.start();
    await tester.pumpWidget(gate(controller));
    await tester.tap(
      find.byKey(const ValueKey('real-account-forgot-password')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Back to log in'));
    await tester.tap(find.text('Back to log in'));
    await tester.pumpAndSettle();
    expect(find.text('Log in to your account'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
  });

  testWidgets('confirmation Back to log in restores login', (tester) async {
    auth.signupOutcome = const EmailSignupOutcome(confirmationRequired: true);
    final controller = buildController();
    await controller.start();
    await controller.signUpWithEmail(
      name: 'Pending',
      email: 'pending@example.invalid',
      password: 'secret123',
    );
    await tester.pumpWidget(gate(controller));
    await tester.tap(find.text('Back to log in'));
    await tester.pumpAndSettle();
    expect(find.text('Log in to your account'), findsOneWidget);
  });

  testWidgets('missing membership onboards before showing app content', (
    tester,
  ) async {
    auth.signIn(signedInA);
    var onboarded = false;
    accounts.onboardHandler = (command) {
      onboarded = true;
      return RepositorySuccess(
        OnboardResult(
          membershipId: 'membership-buyer',
          role: command.role,
          revision: 1,
        ),
      );
    };
    accounts.membershipHandler = (role) => onboarded
        ? RepositorySuccess(membership(id: 'membership-buyer', role: role))
        : const RepositoryFailureResult(
            NotFoundError(entityType: 'membership', entityId: 'buyer'),
          );
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));
    expect(
      find.byKey(const ValueKey('real-account-onboarding-submit')),
      findsOneWidget,
    );
    expect(find.textContaining('ACTIVE APP'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('real-account-onboarding-name')),
      'New Buyer',
    );
    await tester.tap(
      find.byKey(const ValueKey('real-account-onboarding-submit')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ACTIVE APP'), findsOneWidget);
  });

  testWidgets('pending membership blocks app content and can log out', (
    tester,
  ) async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) =>
        RepositorySuccess(membership(status: MembershipStatus.pending));
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));

    expect(
      find.byKey(const ValueKey('real-account-membership-pending')),
      findsOneWidget,
    );
    expect(find.textContaining('ACTIVE APP'), findsNothing);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.byType(ApprovedAccountCreationPage), findsOneWidget);
  });

  testWidgets('restricted membership blocks app content', (tester) async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) =>
        RepositorySuccess(membership(status: MembershipStatus.restricted));
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));

    expect(
      find.byKey(const ValueKey('real-account-membership-restricted')),
      findsOneWidget,
    );
    expect(find.textContaining('ACTIVE APP'), findsNothing);
  });

  testWidgets('backend failure is visible and retryable', (tester) async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) =>
        const RepositoryFailureResult(ServerError(operation: 'select'));
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));
    expect(find.byKey(const ValueKey('real-account-failed')), findsOneWidget);
    expect(find.textContaining('ACTIVE APP'), findsNothing);

    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ACTIVE APP'), findsOneWidget);
  });

  testWidgets('confirmation-pending signup shows a pending state, not access', (
    tester,
  ) async {
    auth.signupOutcome = const EmailSignupOutcome(confirmationRequired: true);
    final controller = buildController();
    await controller.start();
    await controller.signUpWithEmail(
      name: 'Pending',
      email: 'pending@example.invalid',
      password: 'secret123',
    );

    await tester.pumpWidget(gate(controller));

    expect(
      find.byKey(const ValueKey('real-account-confirmation-pending')),
      findsOneWidget,
    );
    expect(find.textContaining('ACTIVE APP'), findsNothing);
  });

  testWidgets('identity replacement unmounts A content until B is authorized', (
    tester,
  ) async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final controller = buildController();
    await controller.start();

    await tester.pumpWidget(gate(controller));
    expect(find.text('ACTIVE APP user-a'), findsOneWidget);

    final pendingB = Completer<RepositoryResult<MembershipRecord>>();
    accounts.membershipFuture = pendingB.future;
    auth.replaceIdentity(
      const AuthIdentitySnapshot(userId: 'user-b', email: 'b@example.invalid'),
    );
    await tester.pump();

    expect(find.textContaining('ACTIVE APP'), findsNothing);
    expect(find.byKey(const ValueKey('real-account-loading')), findsOneWidget);

    accounts.profileHandler = (_) => RepositorySuccess(
      roleProfile(membershipId: 'membership-b', userId: 'user-b'),
    );
    pendingB.complete(
      RepositorySuccess(membership(id: 'membership-b', userId: 'user-b')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE APP user-b'), findsOneWidget);
    expect(find.textContaining('ACTIVE APP user-a'), findsNothing);
  });

  testWidgets('replacement outcomes never show the previous account content', (
    tester,
  ) async {
    final outcomes = <(String, RepositoryResult<MembershipRecord>, String)>[
      (
        'pending',
        RepositorySuccess(
          membership(
            id: 'membership-b',
            userId: 'user-b-pending',
            status: MembershipStatus.pending,
          ),
        ),
        'real-account-membership-pending',
      ),
      (
        'restricted',
        RepositorySuccess(
          membership(
            id: 'membership-b',
            userId: 'user-b-restricted',
            status: MembershipStatus.restricted,
          ),
        ),
        'real-account-membership-restricted',
      ),
      (
        'missing',
        const RepositoryFailureResult(
          NotFoundError(entityType: 'membership', entityId: 'buyer'),
        ),
        'real-account-onboarding-submit',
      ),
      (
        'failed',
        const RepositoryFailureResult(ServerError(operation: 'select')),
        'real-account-failed',
      ),
    ];

    for (final (name, result, expectedKey) in outcomes) {
      accounts.membershipFuture = null;
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      auth.signIn(signedInA);
      final controller = HocalistAccountController(
        auth: auth,
        accounts: accounts,
        newIdempotencyKey: () => 'key',
      );
      await controller.start();

      await tester.pumpWidget(gate(controller));
      expect(find.text('ACTIVE APP user-a'), findsOneWidget, reason: name);

      accounts.membershipFuture = Future.value(result);
      auth.replaceIdentity(
        AuthIdentitySnapshot(
          userId: 'user-b-$name',
          email: 'b-$name@example.invalid',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ACTIVE APP'), findsNothing, reason: name);
      expect(find.byKey(ValueKey(expectedKey)), findsOneWidget, reason: name);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
