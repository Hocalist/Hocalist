import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
// Recovery, authenticated password change and email change. Fakes only: no
// SDK, network, email/SMS or provider call.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/account_recovery_pages.dart';
import 'package:hocalist/features/account/account_security_page.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';
import 'package:hocalist/features/account/real_account_gate.dart';

import 'account_test_fakes.dart';

const signedInA = AuthIdentitySnapshot(
  userId: 'user-a',
  email: 'a@example.invalid',
);

void main() {
  late FakeAuthGateway auth;
  late FakeAccountRepository accounts;
  late int keyCounter;

  setUp(() {
    auth = FakeAuthGateway();
    accounts = FakeAccountRepository();
    keyCounter = 0;
  });

  tearDown(() async {
    await auth.dispose();
  });

  HocalistAccountController buildController() => HocalistAccountController(
    auth: auth,
    accounts: accounts,
    newIdempotencyKey: () => 'key-${++keyCounter}',
  );

  void allowActiveMembership() {
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
  }

  test(
    'a recovery session blocks app content until a new password is set',
    () async {
      auth.signIn(
        const AuthIdentitySnapshot(
          userId: 'user-a',
          email: 'a@example.invalid',
          recovery: true,
        ),
      );
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.phase, AccountAccessPhase.passwordRecovery);
      expect(controller.recoveryActive, isTrue);
      expect(accounts.requestedRoles, isEmpty);
    },
  );

  test('setting the recovered password continues to the normal gate', () async {
    auth.signIn(
      const AuthIdentitySnapshot(
        userId: 'user-a',
        email: 'a@example.invalid',
        recovery: true,
      ),
    );
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.updateRecoveredPassword(password: 'new-password-1');

    expect(auth.updatePasswordValues, ['new-password-1']);
    expect(controller.recoveryActive, isFalse);
    expect(controller.phase, AccountAccessPhase.active);
    expect(accounts.requestedRoles, [HocalistRole.buyer]);
  });

  test(
    'an unacknowledged recovery-clear event keeps the gate closed',
    () async {
      auth.signIn(
        const AuthIdentitySnapshot(
          userId: 'user-a',
          email: 'a@example.invalid',
          recovery: true,
        ),
      );
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      // A provider snapshot without the recovery marker (refresh/user-updated)
      // is not proof that a new password was set.
      auth.completeRecovery(email: 'a@example.invalid');
      await pumpEventQueue();

      expect(controller.phase, AccountAccessPhase.passwordRecovery);
      expect(accounts.requestedRoles, isEmpty);

      // The acknowledged update path completes and continues to the gate.
      await controller.updateRecoveredPassword(password: 'new-password-1');
      expect(controller.phase, AccountAccessPhase.active);
    },
  );

  test(
    'an expired recovery link is a visible state, not a silent login',
    () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      auth.emitRecoverySignal(
        const AccountRecoverySignal(AccountRecoverySignalKind.expired),
      );
      await pumpEventQueue();

      expect(controller.phase, AccountAccessPhase.recoveryLinkExpired);
      expect(
        controller.recoveryLinkFailure?.kind,
        AccountRecoverySignalKind.expired,
      );

      controller.leaveRecoveryLinkExpired();
      expect(controller.phase, AccountAccessPhase.signedOut);
    },
  );

  test('a reset request is a sent-email state, never a login', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.requestPasswordReset(email: 'a@example.invalid');

    expect(auth.passwordResetCalls, 1);
    expect(controller.phase, AccountAccessPhase.recoveryEmailSent);
    expect(controller.recoveryEmail, 'a@example.invalid');
    expect(controller.isSignedIn, isFalse);

    controller.leaveRecoveryEmailSent();
    expect(controller.phase, AccountAccessPhase.signedOut);
  });

  test('an update without a recovery session is rejected', () async {
    auth.signIn(signedInA);
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await expectLater(
      controller.updateRecoveredPassword(password: 'new-password-1'),
      throwsA(
        isA<AccountActionException>().having(
          (error) => error.code,
          'code',
          'recovery_link_invalid',
        ),
      ),
    );
    expect(auth.updatePasswordCalls, 0);
  });

  test('authenticated password change reauthenticates first', () async {
    auth.signIn(signedInA);
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password-1',
    );

    expect(auth.confirmPasswordValues, ['old-password']);
    expect(auth.updatePasswordValues, ['new-password-1']);
    expect(controller.passwordChangeMessage, 'Password updated.');
    expect(controller.phase, AccountAccessPhase.active);
  });

  test('a wrong current password leaves the session untouched', () async {
    auth.signIn(signedInA);
    allowActiveMembership();
    auth.confirmPasswordError = const AccountAuthException(
      'invalid_credentials',
    );
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await expectLater(
      controller.changePassword(
        currentPassword: 'wrong',
        newPassword: 'new-password-1',
      ),
      throwsA(
        isA<AccountActionException>().having(
          (error) => error.message,
          'message',
          'Email or password is not correct.',
        ),
      ),
    );
    expect(auth.updatePasswordCalls, 0);
    expect(controller.phase, AccountAccessPhase.active);
  });

  test('email change reauthenticates and stays pending', () async {
    auth.signIn(signedInA);
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.requestEmailChange(
      newEmail: 'new@example.invalid',
      currentPassword: 'old-password',
    );
    auth.emitPendingEmailChange('new@example.invalid');
    await pumpEventQueue();

    expect(auth.emailChangeValues, ['new@example.invalid']);
    expect(controller.pendingEmailChange, 'new@example.invalid');
    expect(controller.email, 'a@example.invalid');
    expect(controller.phase, AccountAccessPhase.active);
  });

  testWidgets('the gate renders the recovery password page, not app content', (
    tester,
  ) async {
    auth.signIn(
      const AuthIdentitySnapshot(
        userId: 'user-a',
        email: 'a@example.invalid',
        recovery: true,
      ),
    );
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        home: HocalistRealAccountGate(
          controller: controller,
          activeBuilder: (_, _) => const Text('marketplace-content'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('account-recovery-password')),
      findsOneWidget,
    );
    expect(find.text('marketplace-content'), findsNothing);
  });

  testWidgets('the expired-link page explains the failure', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AccountRecoveryLinkExpiredPage(expired: true, onBack: () {}),
      ),
    );
    expect(
      find.byKey(const ValueKey('account-recovery-link-failed')),
      findsOneWidget,
    );
    expect(find.text('Reset link expired'), findsOneWidget);
  });

  testWidgets('Settings Security shows controls without a second navigation', (
    tester,
  ) async {
    auth.signIn(signedInA);
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovedSellerSettingsPage(
              darkMode: false,
              textSizeLabel: 'Medium',
              onAccessibility: () {},
              onBack: () {},
              onEditProfile: () {},
              onThemeChanged: (_) {},
              securityContent: AccountSecurityPage(
                controller: controller,
                onBack: () => throw StateError('Unexpected nested route'),
                embedded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('security-current-password')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('security-password-submit')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('security-new-email')), findsOneWidget);
    expect(find.text('Password & security'), findsNothing);
    expect(find.byKey(const ValueKey('security-back')), findsNothing);
  });
  testWidgets('the security page exposes password and email changes', (
    tester,
  ) async {
    auth.signIn(signedInA);
    allowActiveMembership();
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSecurityPage(controller: controller, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('security-current-email')),
      findsOneWidget,
    );
    expect(find.textContaining('a@example.invalid'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('security-current-password')),
      'old-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('security-new-password')),
      'new-password-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('security-confirm-password')),
      'new-password-1',
    );
    await tester.tap(find.byKey(const ValueKey('security-password-submit')));
    await tester.pumpAndSettle();

    expect(auth.updatePasswordValues, ['new-password-1']);
    expect(find.byKey(const ValueKey('security-message')), findsOneWidget);
  });
}
