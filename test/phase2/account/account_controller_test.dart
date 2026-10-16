// Focused controller tests for the real account wiring. Fakes only: no SDK,
// no network, no provider call and no device state.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/patch.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';
import 'package:hocalist/features/account/hocalist_account_controller.dart';

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

  HocalistAccountController buildController({
    Future<void> Function()? disablePush,
  }) {
    return HocalistAccountController(
      auth: auth,
      accounts: accounts,
      disablePush: disablePush,
      newIdempotencyKey: () => 'key-${++keyCounter}',
    );
  }

  Future<void> flush() => pumpEventQueue();

  test(
    'a restored explicit seller choice never loads the buyer membership',
    () async {
      auth.signIn(signedInA);
      final controller = HocalistAccountController(
        auth: auth,
        accounts: accounts,
        initialRole: HocalistRole.seller,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.selectedRole, HocalistRole.seller);
      expect(accounts.requestedRoles, [HocalistRole.seller]);
      expect(controller.phase, AccountAccessPhase.onboarding);
    },
  );

  test(
    'restores a provider session and the explicitly selected membership',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      accounts.contactHandler = () => RepositorySuccess(privateContact());
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.phase, AccountAccessPhase.active);
      expect(controller.membership?.userId, 'user-a');
      expect(controller.profile?.displayName, 'Synthetic Buyer');
      expect(controller.email, 'a@example.invalid');
      expect(accounts.requestedRoles, [HocalistRole.buyer]);
    },
  );

  test(
    'starts signed out without a provider session and reads nothing',
    () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.phase, AccountAccessPhase.signedOut);
      expect(accounts.requestedRoles, isEmpty);
    },
  );

  test('email link request waits for a confirmed identity', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();
    await controller.requestEmailLink(
      email: 'buyer@example.invalid',
      name: 'Buyer Test',
    );
    expect(auth.emailLinkCalls, 1);
    expect(controller.phase, AccountAccessPhase.signedOut);
    expect(controller.awaitingProvider, isTrue);
    expect(accounts.requestedRoles, isEmpty);
  });

  test(
    'selects the seller role explicitly and fetches that role only',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (role) => RepositorySuccess(
        membership(
          id: 'membership-${role.name}',
          role: role,
          status: MembershipStatus.pending,
        ),
      );
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.membershipPending);

      controller.selectRole(HocalistRole.seller);
      await flush();

      expect(controller.selectedRole, HocalistRole.seller);
      expect(accounts.requestedRoles, [
        HocalistRole.buyer,
        HocalistRole.seller,
      ]);
      expect(controller.membership?.role, HocalistRole.seller);
    },
  );

  test('missing membership onboards with a stable retry key', () async {
    auth.signIn(signedInA);
    var attempts = 0;
    var onboarded = false;
    accounts.onboardHandler = (command) {
      attempts += 1;
      if (attempts == 1) {
        return const RepositoryFailureResult(NetworkError());
      }
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
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.phase, AccountAccessPhase.onboarding);

    await expectLater(
      controller.onboardSelectedRole(displayName: 'Retry Buyer'),
      throwsA(
        isA<AccountActionException>().having((e) => e.code, 'code', 'network'),
      ),
    );
    await controller.onboardSelectedRole(displayName: 'Retry Buyer');

    expect(controller.phase, AccountAccessPhase.active);
    expect(accounts.onboardCommands, hasLength(2));
    expect(
      accounts.onboardCommands[0].idempotencyKey,
      accounts.onboardCommands[1].idempotencyKey,
    );
    expect(accounts.onboardCommands[1].role, HocalistRole.buyer);
  });

  test('changed onboarding payload gets a new key', () async {
    auth.signIn(signedInA);
    accounts.onboardHandler = (command) =>
        const RepositoryFailureResult(NetworkError());
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await expectLater(
      controller.onboardSelectedRole(displayName: 'First'),
      throwsA(isA<AccountActionException>()),
    );
    await expectLater(
      controller.onboardSelectedRole(displayName: 'Second'),
      throwsA(isA<AccountActionException>()),
    );

    expect(accounts.onboardCommands, hasLength(2));
    expect(
      accounts.onboardCommands[0].idempotencyKey,
      isNot(accounts.onboardCommands[1].idempotencyKey),
    );
  });

  test(
    'duplicate onboarding submit is rejected while one is in flight',
    () async {
      auth.signIn(signedInA);
      final pending = Completer<RepositoryResult<OnboardResult>>();
      accounts.onboardFuture = pending.future;
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.onboarding);

      final first = controller.onboardSelectedRole(displayName: 'Slow');
      await expectLater(
        controller.onboardSelectedRole(displayName: 'Slow'),
        throwsA(
          isA<AccountActionException>().having(
            (e) => e.code,
            'code',
            'duplicate_submit',
          ),
        ),
      );
      expect(accounts.onboardCommands, hasLength(1));
      pending.complete(
        RepositorySuccess(
          OnboardResult(
            membershipId: 'membership-buyer',
            role: HocalistRole.buyer,
            revision: 1,
          ),
        ),
      );
      await first;
    },
  );

  test(
    'confirmation-pending signup is not a login and fetches nothing',
    () async {
      auth.signupOutcome = const EmailSignupOutcome(confirmationRequired: true);
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      await controller.signUpWithEmail(
        name: 'Pending Buyer',
        email: 'pending@example.invalid',
        password: 'secret123',
      );

      expect(controller.phase, AccountAccessPhase.emailConfirmationPending);
      expect(controller.isSignedIn, isFalse);
      expect(accounts.requestedRoles, isEmpty);
      expect(controller.email, 'pending@example.invalid');

      controller.leaveConfirmationPending();
      expect(controller.phase, AccountAccessPhase.signedOut);
    },
  );

  test('confirmed email signup proceeds to onboarding', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.signUpWithEmail(
      name: 'Fresh Buyer',
      email: 'fresh@example.invalid',
      password: 'secret123',
    );

    expect(controller.isSignedIn, isTrue);
    expect(controller.phase, AccountAccessPhase.onboarding);
    expect(controller.suggestedDisplayName, 'Fresh Buyer');
  });

  test('auth errors map to safe actionable messages', () async {
    auth.loginError = const AccountAuthException('invalid_credentials');
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    await expectLater(
      controller.logInWithEmail(email: 'a@example.invalid', password: 'wrong'),
      throwsA(
        isA<AccountActionException>()
            .having((e) => e.code, 'code', 'invalid_credentials')
            .having(
              (e) => e.message,
              'message',
              'Email or password is not correct.',
            ),
      ),
    );
    expect(controller.phase, AccountAccessPhase.signedOut);
  });

  test(
    'restricted membership never loads the profile or reaches active',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) =>
          RepositorySuccess(membership(status: MembershipStatus.restricted));
      var profileFetches = 0;
      accounts.profileHandler = (_) {
        profileFetches += 1;
        return RepositorySuccess(roleProfile());
      };
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.phase, AccountAccessPhase.membershipRestricted);
      expect(profileFetches, 0);
    },
  );

  test('pending membership stays pending and never reaches active', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) =>
        RepositorySuccess(membership(status: MembershipStatus.pending));
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.phase, AccountAccessPhase.membershipPending);
    expect(controller.profile, isNull);
  });

  test('backend failure is an honest retryable state', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) =>
        const RepositoryFailureResult(ServerError(operation: 'select'));
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.phase, AccountAccessPhase.failed);
    expect(controller.errorMessage, isNotNull);

    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    await controller.refresh();
    expect(controller.phase, AccountAccessPhase.active);
  });

  test('contact read failure does not block active access', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    accounts.contactHandler = () =>
        const RepositoryFailureResult(ServerError(operation: 'select'));
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.phase, AccountAccessPhase.active);
    expect(controller.contact, isNull);
    expect(controller.contactUnavailable, isTrue);
  });

  test(
    'logout cleans up push before sign-out and clears private state',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      final controller = buildController(
        disablePush: () async => auth.logoutOrder.add('disablePush'),
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.active);

      await controller.logout();

      expect(auth.logoutOrder, ['cleanup', 'disablePush', 'signOut']);
      expect(controller.phase, AccountAccessPhase.signedOut);
      expect(controller.profile, isNull);
      expect(controller.email, isNull);
      expect(controller.isSignedIn, isFalse);
    },
  );

  test('logout cleanup failure still signs the user out', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final controller = buildController(
      disablePush: () async => throw StateError('push cleanup failed'),
    );
    addTearDown(controller.dispose);
    await controller.start();

    await controller.logout();

    expect(controller.phase, AccountAccessPhase.signedOut);
    expect(controller.isSignedIn, isFalse);
    expect(auth.currentIdentity.userId, isNull);
  });

  test('logout does not sign out a replacement identity', () async {
    auth.signIn(signedInA);
    var activeUser = 'user-a';
    accounts.membershipHandler = (_) => RepositorySuccess(
      membership(id: 'membership-$activeUser', userId: activeUser),
    );
    accounts.profileHandler = (_) => RepositorySuccess(
      roleProfile(membershipId: 'membership-$activeUser', userId: activeUser),
    );
    final controller = buildController(
      disablePush: () async {
        activeUser = 'user-b';
        auth.replaceIdentity(
          const AuthIdentitySnapshot(
            userId: 'user-b',
            email: 'b@example.invalid',
          ),
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.start();

    await controller.logout();
    await flush();

    expect(auth.currentIdentity.userId, 'user-b');
    expect(controller.isSignedIn, isTrue);
    expect(controller.phase, AccountAccessPhase.active);
    expect(controller.membership?.userId, 'user-b');
  });

  test(
    'stale membership results are discarded after an identity change',
    () async {
      auth.signIn(signedInA);
      final stale = Completer<RepositoryResult<MembershipRecord>>();
      accounts.membershipFuture = stale.future;
      final controller = buildController();
      addTearDown(controller.dispose);

      final started = controller.start();
      await flush();
      expect(controller.busy, isTrue);

      // The replacement identity resolves immediately with its own membership.
      accounts.membershipFuture = Future.value(
        RepositorySuccess(membership(id: 'membership-b', userId: 'user-b')),
      );
      accounts.profileHandler = (_) => RepositorySuccess(
        roleProfile(membershipId: 'membership-b', userId: 'user-b'),
      );
      auth.replaceIdentity(
        const AuthIdentitySnapshot(
          userId: 'user-b',
          email: 'b@example.invalid',
        ),
      );
      await flush();
      expect(controller.phase, AccountAccessPhase.active);
      expect(controller.membership?.userId, 'user-b');

      // The first identity's response arrives late and must be ignored.
      stale.complete(
        RepositorySuccess(membership(id: 'membership-a', userId: 'user-a')),
      );
      await started;
      await flush();
      expect(controller.membership?.userId, 'user-b');
      expect(controller.phase, AccountAccessPhase.active);
    },
  );

  test(
    'identity replacement closes the gate before the new role resolves',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.active);

      final pendingB = Completer<RepositoryResult<MembershipRecord>>();
      accounts.membershipFuture = pendingB.future;
      auth.replaceIdentity(
        const AuthIdentitySnapshot(
          userId: 'user-b',
          email: 'b@example.invalid',
        ),
      );
      await flush();

      // The previous identity's app content is closed while B is unresolved.
      expect(controller.phase, AccountAccessPhase.booting);
      expect(controller.busy, isTrue);
      expect(controller.membership, isNull);
      expect(controller.profile, isNull);
      expect(controller.email, 'b@example.invalid');

      accounts.profileHandler = (_) => RepositorySuccess(
        roleProfile(membershipId: 'membership-b', userId: 'user-b'),
      );
      pendingB.complete(
        RepositorySuccess(membership(id: 'membership-b', userId: 'user-b')),
      );
      await flush();

      expect(controller.phase, AccountAccessPhase.active);
      expect(controller.membership?.userId, 'user-b');
      expect(controller.profile?.userId, 'user-b');
    },
  );

  test(
    'a replacement with a restricted membership never becomes active',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.active);

      accounts.membershipFuture = Future.value(
        RepositorySuccess(
          membership(
            id: 'membership-b',
            userId: 'user-b',
            status: MembershipStatus.restricted,
          ),
        ),
      );
      auth.replaceIdentity(
        const AuthIdentitySnapshot(
          userId: 'user-b',
          email: 'b@example.invalid',
        ),
      );
      await flush();

      expect(controller.phase, AccountAccessPhase.membershipRestricted);
      expect(controller.profile, isNull);
    },
  );

  test('logout failure keeps the session and reports a safe error', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.phase, AccountAccessPhase.active);

    auth.failLogoutWithoutSignOut = true;
    await expectLater(
      controller.logout(),
      throwsA(
        isA<AccountActionException>()
            .having((e) => e.code, 'code', 'logout_failed')
            .having(
              (e) => e.message,
              'message',
              'Could not sign out. Try again.',
            ),
      ),
    );

    expect(controller.isSignedIn, isTrue);
    expect(controller.phase, AccountAccessPhase.active);
    expect(controller.busy, isFalse);
  });

  test(
    'same-user token refresh keeps the active phase without reloading',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.phase, AccountAccessPhase.active);
      final fetchesBefore = accounts.requestedRoles.length;

      auth.replaceIdentity(
        const AuthIdentitySnapshot(
          userId: 'user-a',
          email: 'a@example.invalid',
        ),
      );
      await flush();

      expect(controller.phase, AccountAccessPhase.active);
      expect(controller.membership?.userId, 'user-a');
      expect(accounts.requestedRoles.length, fetchesBefore);
    },
  );

  test('logout during a pending replacement load stays signed out', () async {
    auth.signIn(signedInA);
    accounts.membershipHandler = (_) => RepositorySuccess(membership());
    accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.start();

    final pendingB = Completer<RepositoryResult<MembershipRecord>>();
    accounts.membershipFuture = pendingB.future;
    auth.replaceIdentity(
      const AuthIdentitySnapshot(userId: 'user-b', email: 'b@example.invalid'),
    );
    await flush();
    expect(controller.phase, AccountAccessPhase.booting);

    await controller.logout();
    expect(controller.phase, AccountAccessPhase.signedOut);

    pendingB.complete(
      RepositorySuccess(membership(id: 'membership-b', userId: 'user-b')),
    );
    await flush();

    expect(controller.phase, AccountAccessPhase.signedOut);
    expect(controller.membership, isNull);
    expect(controller.isSignedIn, isFalse);
  });

  test(
    'display name update keeps the expected revision and key on retry',
    () async {
      auth.signIn(signedInA);
      var revision = 3;
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(
        roleProfile(
          displayName: revision == 3 ? 'Before' : 'After',
          revision: revision,
        ),
      );
      var attempts = 0;
      accounts.profileUpdateHandler = (command) {
        attempts += 1;
        if (attempts == 1) {
          return const RepositoryFailureResult(NetworkError());
        }
        revision = command.expectedRevision + 1;
        return RepositorySuccess(
          RoleProfileUpdateResult(
            profileId: command.profileId,
            revision: revision,
          ),
        );
      };
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      await expectLater(
        controller.updateDisplayName('After'),
        throwsA(isA<AccountActionException>()),
      );
      await controller.updateDisplayName('After');

      expect(accounts.profileUpdateCommands, hasLength(2));
      expect(accounts.profileUpdateCommands[0].expectedRevision, 3);
      expect(
        accounts.profileUpdateCommands[0].idempotencyKey,
        accounts.profileUpdateCommands[1].idempotencyKey,
      );
      expect(controller.profile?.displayName, 'After');
      expect(controller.profile?.stamp.revision, 4);
    },
  );

  test(
    'profile detail command preserves captured revision and rejects wrong membership',
    () async {
      auth.signIn(signedInA);
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) =>
          RepositorySuccess(roleProfile(revision: 4));
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();
      final command = UpdateRoleProfileCommand(
        profileId: 'membership-1',
        expectedRevision: 3,
        displayName: 'Synthetic Buyer',
        areaLabel: const PatchSet('Chicago'),
        idempotencyKey: 'captured-profile-intent',
      );
      await controller.updateProfileDetails(command);
      expect(accounts.profileUpdateCommands.single, same(command));
      expect(accounts.profileUpdateCommands.single.expectedRevision, 3);
      await expectLater(
        controller.updateProfileDetails(
          UpdateRoleProfileCommand(
            profileId: 'another-membership',
            expectedRevision: 1,
            displayName: 'Other',
            idempotencyKey: 'forged',
          ),
        ),
        throwsA(isA<AccountActionException>()),
      );
      expect(accounts.profileUpdateCommands, hasLength(1));
    },
  );

  test(
    'contact update uses its own revision and stable key on retry',
    () async {
      auth.signIn(signedInA);
      var revision = 1;
      accounts.membershipHandler = (_) => RepositorySuccess(membership());
      accounts.profileHandler = (_) => RepositorySuccess(roleProfile());
      accounts.contactHandler = () =>
          RepositorySuccess(privateContact(revision: revision));
      var attempts = 0;
      accounts.contactUpdateHandler = (command) {
        attempts += 1;
        if (attempts == 1) {
          return const RepositoryFailureResult(NetworkError());
        }
        revision = command.expectedRevision + 1;
        return RepositorySuccess(ContactUpdateResult(revision: revision));
      };
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.start();

      UpdateContactCommand build(PrivateContactRecord current) =>
          UpdateContactCommand(
            expectedRevision: current.stamp.revision,
            phone: const PatchSet<String>('+14155550123'),
            idempotencyKey: 'caller-key',
          );

      await expectLater(
        controller.updateContact(build),
        throwsA(isA<AccountActionException>()),
      );
      await controller.updateContact(build);

      expect(accounts.contactUpdateCommands, hasLength(2));
      expect(accounts.contactUpdateCommands[0].expectedRevision, 1);
      expect(
        accounts.contactUpdateCommands[0].idempotencyKey,
        accounts.contactUpdateCommands[1].idempotencyKey,
      );
      expect(controller.contact?.stamp.revision, 2);
    },
  );
}
