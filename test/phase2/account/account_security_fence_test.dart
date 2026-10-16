// Regression probes for the reviewer findings:
// 1. An ordinary same-user session event must not clear a recovery gate.
// 2. A sensitive multi-step action must not continue after identity
//    replacement while it is awaiting reauthentication.
// Fakes only: no SDK, network or provider call.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';

import 'account_test_fakes.dart';

const signedInA = AuthIdentitySnapshot(
  userId: 'user-a',
  email: 'a@example.invalid',
);
const signedInB = AuthIdentitySnapshot(
  userId: 'user-b',
  email: 'b@example.invalid',
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

  Matcher sessionChanged() => isA<AccountActionException>().having(
    (error) => error.code,
    'code',
    'session_changed',
  );

  test(
    'an ordinary same-user recovery=false event does not clear the gate',
    () async {
      auth.startRecovery();
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.passwordRecovery);

      // What a leaky gateway emits on token refresh / userUpdated: the same
      // identity without the recovery marker. It is not a completed reset.
      auth.emitRawIdentity(signedInA);
      await pumpEventQueue();

      expect(controller.phase, AccountAccessPhase.passwordRecovery);
      expect(controller.recoveryActive, isTrue);
      expect(accounts.requestedRoles, isEmpty);
    },
  );

  test(
    'a replacement during reauthentication stops the password mutation',
    () async {
      auth.signIn(signedInA);
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      auth.confirmPasswordGate = Completer<void>();
      final action = controller.changePassword(
        currentPassword: 'old-password',
        newPassword: 'new-password-1',
      );
      await pumpEventQueue();
      expect(auth.confirmPasswordCalls, 1);

      auth.signIn(signedInB);
      auth.confirmPasswordGate!.complete();
      await expectLater(action, throwsA(sessionChanged()));

      expect(auth.updatePasswordCalls, 0);
    },
  );

  test(
    'a replacement during recovered-password update stops completion',
    () async {
      auth.startRecovery();
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      auth.updatePasswordGate = Completer<void>();
      final action = controller.updateRecoveredPassword(
        password: 'new-password-1',
      );
      await pumpEventQueue();
      expect(auth.updatePasswordCalls, 1);

      auth.signOut();
      auth.updatePasswordGate!.complete();
      await expectLater(action, throwsA(sessionChanged()));

      expect(controller.phase, AccountAccessPhase.signedOut);
    },
  );

  test(
    'a replacement during reauthentication stops the email change',
    () async {
      auth.signIn(signedInA);
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      auth.confirmPasswordGate = Completer<void>();
      final action = controller.requestEmailChange(
        newEmail: 'new@example.invalid',
        currentPassword: 'old-password',
      );
      await pumpEventQueue();
      auth.signIn(signedInB);
      auth.confirmPasswordGate!.complete();
      await expectLater(action, throwsA(sessionChanged()));

      expect(auth.emailChangeCalls, 0);
    },
  );

  test(
    'a replacement during reauthentication stops a reauthenticate action',
    () async {
      auth.signIn(signedInA);
      allowActiveMembership();
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      auth.confirmPasswordGate = Completer<void>();
      final action = controller.reauthenticate('old-password');
      await pumpEventQueue();
      auth.signIn(signedInB);
      auth.confirmPasswordGate!.complete();
      await expectLater(action, throwsA(sessionChanged()));
    },
  );
}
