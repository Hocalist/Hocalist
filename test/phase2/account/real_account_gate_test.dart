// Widget tests for the real account gate phases. Fakes only; the gate must
// never render app content for missing, pending, restricted or failed states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/account/real_account_gate.dart';
import 'package:hocalist/features/approved/onboarding_home_pages.dart';

import 'account_test_fakes.dart';
import 'package:hocalist/features/seller/approved_seller_tutorial_page.dart';

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

  test(
    'phone signup name survives the authenticated identity transition',
    () async {
      final controller = buildController();
      await controller.start();
      await controller.requestPhoneCode(
        phone: '+14155550123',
        signup: true,
        name: 'Phone Buyer',
      );
      await controller.confirmPhoneCode(
        phone: '+14155550123',
        code: '123456',
        name: 'Phone Buyer',
      );
      expect(controller.suggestedDisplayName, 'Phone Buyer');
      expect(controller.userId, 'user-a');
    },
  );

  testWidgets('real signup role changes retain typed email and password', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = buildController();
    await controller.start();
    await tester.pumpWidget(gate(controller));
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-email-field')),
      'new@example.invalid',
    );
    await tester.enterText(
      find.byKey(const ValueKey('approved-account-password-field')),
      'test-pass-123',
    );
    await tester.ensureVisible(find.text('I am selling'));
    await tester.tap(find.text('I am selling'));
    await tester.pumpAndSettle();
    expect(controller.selectedRole, HocalistRole.seller);
    for (final entry in {
      'email': 'new@example.invalid',
      'password': 'test-pass-123',
    }.entries) {
      final input = find.descendant(
        of: find.byKey(ValueKey('approved-account-${entry.key}-field')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(input).controller.text, entry.value);
    }
  });

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
        isNotNull,
      );
    }
  });

  testWidgets('recovery Back to log in restores login instead of signup', (
    tester,
  ) async {
    final controller = buildController();
    await controller.start();
    await tester.pumpWidget(gate(controller));
    await tester.ensureVisible(find.text('Log in'));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('approved-account-forgot-password')),
    );
    await tester.tap(
      find.byKey(const ValueKey('approved-account-forgot-password')),
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

    expect(find.byType(ApprovedBuyerBenefitsPage), findsOneWidget);
    tester.widget<ApprovedBuyerBenefitsPage>(find.byType(ApprovedBuyerBenefitsPage)).onFinish();
    await tester.pumpAndSettle();
    expect(find.textContaining('ACTIVE APP'), findsOneWidget);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(ApprovedBuyerBenefitsPage), findsNothing);
  });

  testWidgets('new seller sees its own introduction before the app', (tester) async {
    auth.signIn(signedInA);
    var created = false;
    accounts.membershipHandler = (role) => created
        ? RepositorySuccess(membership(role: role))
        : const RepositoryFailureResult(NotFoundError(entityType: 'membership', entityId: 'seller'));
    accounts.profileHandler = (role) => RepositorySuccess(roleProfile(role: role));
    accounts.onboardHandler = (command) {
      created = true;
      return RepositorySuccess(OnboardResult(membershipId: 'membership-1', role: command.role, revision: 1));
    };
    final controller = HocalistAccountController(auth: auth, accounts: accounts, initialRole: HocalistRole.seller);
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(gate(controller));
    await controller.onboardSelectedRole(displayName: 'New Seller');
    await tester.pumpAndSettle();
    expect(find.byType(ApprovedBuyerBenefitsPage), findsNothing);
    tester.widget<ApprovedSellerTutorialPage>(find.byType(ApprovedSellerTutorialPage)).onContinue();
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE APP user-a'), findsOneWidget);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(ApprovedSellerTutorialPage), findsNothing);
  });

  testWidgets('onboarding centers logo and form without a scrolling page', (
    tester,
  ) async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => const RepositoryFailureResult(
      NotFoundError(entityType: 'membership', entityId: 'buyer'),
    );
    final controller = buildController();
    await controller.start();
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      tester.view.resetPhysicalSize();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      for (final scale in [1.0, 1.15, 1.3, 1.6]) {
        for (final keyboard in [0.0, 320.0]) {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: child!,
              ),
              home: HocalistRealAccountGate(
                controller: controller,
                activeBuilder: (_, _) => const SizedBox(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final group = tester.getRect(
            find.byKey(const ValueKey('real-account-onboarding-group')),
          );
          final logo = tester.getRect(
            find.byKey(const ValueKey('real-account-onboarding-logo')),
          );
          final heading = tester.getRect(
            find.text('Finish your buyer account'),
          );
          expect(logo.bottom, lessThan(heading.top));
          expect(group.center.dy, closeTo((844 - keyboard) / 2, 1));
          expect(group.top, greaterThanOrEqualTo(0));
          expect(group.bottom, lessThanOrEqualTo(844 - keyboard));
          expect(
            find.ancestor(
              of: find.byKey(const ValueKey('real-account-onboarding-group')),
              matching: find.byType(Scrollable),
            ),
            findsNothing,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width / $scale / $keyboard',
          );
        }
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
