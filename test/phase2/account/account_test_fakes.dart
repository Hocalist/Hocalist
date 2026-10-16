// Shared fakes for the real account wiring tests. No network, SDK, provider
// or plugin is touched.
import 'dart:async';

import 'package:hocalist/domain/phase2/account_contacts.dart';
import 'package:hocalist/domain/phase2/accounts.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/profiles.dart';
import 'package:hocalist/features/account/account_auth_gateway.dart';

RecordStamp stamp(int revision) => RecordStamp(
  revision: revision,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
);

MembershipRecord membership({
  String id = 'membership-1',
  String userId = 'user-a',
  HocalistRole role = HocalistRole.buyer,
  MembershipStatus status = MembershipStatus.active,
  int revision = 1,
}) => MembershipRecord(
  membershipId: id,
  userId: userId,
  role: role,
  status: status,
  stamp: stamp(revision),
);

AccountRoleProfile roleProfile({
  String membershipId = 'membership-1',
  String userId = 'user-a',
  HocalistRole role = HocalistRole.buyer,
  String displayName = 'Synthetic Buyer',
  int revision = 1,
  String? areaLabel,
  String? profileNote,
}) => AccountRoleProfile(
  membershipId: membershipId,
  userId: userId,
  role: role,
  displayName: displayName,
  areaLabel: areaLabel,
  profileNote: profileNote,
  stamp: stamp(revision),
);

PrivateContactRecord privateContact({
  String userId = 'user-a',
  String? phone,
  String? city,
  int revision = 1,
}) => PrivateContactRecord(
  userId: userId,
  contact: AccountContact(phone: phone, city: city),
  stamp: stamp(revision),
);

class FakeAuthGateway implements AccountAuthGateway {
  FakeAuthGateway({AuthIdentitySnapshot? identity})
    : _identity = identity ?? const AuthIdentitySnapshot.signedOut();

  final StreamController<AuthIdentitySnapshot> _controller =
      StreamController<AuthIdentitySnapshot>.broadcast();
  final StreamController<AccountRecoverySignal> _recoveryController =
      StreamController<AccountRecoverySignal>.broadcast();

  AuthIdentitySnapshot _identity;
  EmailSignupOutcome signupOutcome = const EmailSignupOutcome(
    confirmationRequired: false,
  );
  Object? signupError;
  Object? loginError;
  Object? googleError;
  Object? emailLinkError;
  Object? phoneRequestError;
  Object? phoneConfirmError;
  Object? logoutError;
  Object? passwordResetError;
  Object? updatePasswordError;
  Object? emailChangeError;
  Object? confirmPasswordError;

  int signupCalls = 0;
  int loginCalls = 0;
  int googleCalls = 0;
  int emailLinkCalls = 0;
  int phoneRequestCalls = 0;
  int phoneConfirmCalls = 0;
  int passwordResetCalls = 0;
  int updatePasswordCalls = 0;
  int emailChangeCalls = 0;
  int confirmPasswordCalls = 0;
  final List<String> updatePasswordValues = <String>[];
  final List<String> confirmPasswordValues = <String>[];
  final List<String> emailChangeValues = <String>[];
  final List<String> logoutOrder = <String>[];

  /// Test gates that hold a provider call open across an identity change.
  Completer<void>? confirmPasswordGate;
  Completer<void>? updatePasswordGate;

  @override
  AuthIdentitySnapshot get currentIdentity => _identity;

  @override
  Stream<AuthIdentitySnapshot> get identityChanges => _controller.stream;

  @override
  Stream<AccountRecoverySignal> get recoverySignals =>
      _recoveryController.stream;

  void signIn(AuthIdentitySnapshot identity) {
    _identity = identity;
    _controller.add(identity);
  }

  void replaceIdentity(AuthIdentitySnapshot identity) => signIn(identity);

  void signOut() => signIn(const AuthIdentitySnapshot.signedOut());

  /// Simulates a consumed recovery link for the current identity.
  void startRecovery({
    String userId = 'user-a',
    String? email = 'a@example.com',
  }) {
    signIn(AuthIdentitySnapshot(userId: userId, email: email, recovery: true));
  }

  /// Simulates the provider's acknowledged post-password-update event. This is
  /// the only event that completes a reset; [updatePassword] emits it, and a
  /// leaky gateway can be modeled with [emitRawIdentity].
  void completeRecovery({
    String userId = 'user-a',
    String? email = 'a@example.com',
  }) {
    signIn(AuthIdentitySnapshot(userId: userId, email: email, recovery: false));
  }

  /// Emits any identity snapshot without gateway semantics, modeling what an
  /// unlatched provider refresh would deliver.
  void emitRawIdentity(AuthIdentitySnapshot identity) => signIn(identity);

  void emitRecoverySignal(AccountRecoverySignal signal) =>
      _recoveryController.add(signal);

  void emitPendingEmailChange(String address) {
    signIn(
      AuthIdentitySnapshot(
        userId: _identity.userId,
        email: _identity.email,
        recovery: _identity.recovery,
        pendingEmailChange: address,
      ),
    );
  }

  @override
  Future<EmailSignupOutcome> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    signupCalls += 1;
    if (signupError != null) throw signupError!;
    if (!signupOutcome.confirmationRequired) {
      signIn(AuthIdentitySnapshot(userId: 'user-a', email: email));
    }
    return signupOutcome;
  }

  @override
  Future<void> logInWithEmail({
    required String email,
    required String password,
  }) async {
    loginCalls += 1;
    if (loginError != null) throw loginError!;
    signIn(AuthIdentitySnapshot(userId: 'user-a', email: email));
  }

  @override
  Future<void> signInWithGoogle() async {
    googleCalls += 1;
    if (googleError != null) throw googleError!;
  }

  @override
  Future<void> requestEmailLink({
    required String email,
    required String name,
  }) async {
    emailLinkCalls += 1;
    if (emailLinkError != null) throw emailLinkError!;
  }

  @override
  Future<void> requestPhoneCode({
    required String phone,
    required bool signup,
  }) async {
    phoneRequestCalls += 1;
    if (phoneRequestError != null) throw phoneRequestError!;
  }

  @override
  Future<void> confirmPhoneCode({
    required String phone,
    required String code,
  }) async {
    phoneConfirmCalls += 1;
    if (phoneConfirmError != null) throw phoneConfirmError!;
    signIn(const AuthIdentitySnapshot(userId: 'user-a', email: null));
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    passwordResetCalls += 1;
    if (passwordResetError != null) throw passwordResetError!;
  }

  @override
  Future<void> updatePassword({required String password}) async {
    updatePasswordCalls += 1;
    updatePasswordValues.add(password);
    if (updatePasswordGate != null) await updatePasswordGate!.future;
    if (updatePasswordError != null) throw updatePasswordError!;
    // A successful provider password update acknowledges and clears the
    // recovery latch for the same identity, exactly like the real gateway.
    if (_identity.recovery && _identity.userId != null) {
      completeRecovery(userId: _identity.userId!, email: _identity.email);
    }
  }

  @override
  Future<void> requestEmailChange({required String newEmail}) async {
    emailChangeCalls += 1;
    emailChangeValues.add(newEmail);
    if (emailChangeError != null) throw emailChangeError!;
  }

  @override
  Future<void> confirmPassword({required String password}) async {
    confirmPasswordCalls += 1;
    confirmPasswordValues.add(password);
    if (confirmPasswordGate != null) await confirmPasswordGate!.future;
    if (confirmPasswordError != null) throw confirmPasswordError!;
  }

  /// Simulates a local sign-out that fails and leaves the session in place.
  bool failLogoutWithoutSignOut = false;

  @override
  Future<void> logout({required Future<void> Function() disablePush}) async {
    final captured = _identity.userId;
    logoutOrder.add('cleanup');
    if (failLogoutWithoutSignOut) {
      throw const AccountAuthException('logout_failed');
    }
    try {
      await disablePush();
    } finally {
      if (_identity.userId == captured) {
        logoutOrder.add('signOut');
        _identity = const AuthIdentitySnapshot.signedOut();
        _controller.add(_identity);
      }
    }
  }

  Future<void> dispose() async {
    await _controller.close();
    await _recoveryController.close();
  }
}

class FakeAccountRepository implements AccountRepository {
  Future<RepositoryResult<MembershipRecord>>? membershipFuture;
  Future<RepositoryResult<OnboardResult>>? onboardFuture;
  RepositoryResult<MembershipRecord> Function(HocalistRole role)?
  membershipHandler;
  RepositoryResult<AccountRoleProfile> Function(HocalistRole role)?
  profileHandler;
  RepositoryResult<PrivateContactRecord> Function()? contactHandler;
  RepositoryResult<OnboardResult> Function(OnboardCommand command)?
  onboardHandler;
  RepositoryResult<RoleProfileUpdateResult> Function(
    UpdateRoleProfileCommand command,
  )?
  profileUpdateHandler;
  RepositoryResult<ContactUpdateResult> Function(UpdateContactCommand command)?
  contactUpdateHandler;

  final List<HocalistRole> requestedRoles = <HocalistRole>[];
  final List<OnboardCommand> onboardCommands = <OnboardCommand>[];
  final List<UpdateRoleProfileCommand> profileUpdateCommands =
      <UpdateRoleProfileCommand>[];
  final List<UpdateContactCommand> contactUpdateCommands =
      <UpdateContactCommand>[];

  @override
  Future<RepositoryResult<List<MembershipRecord>>> fetchMemberships() async {
    return const RepositorySuccess(<MembershipRecord>[]);
  }

  @override
  Future<RepositoryResult<MembershipRecord>> fetchMembership({
    required HocalistRole role,
  }) async {
    requestedRoles.add(role);
    final future = membershipFuture;
    if (future != null) return future;
    final handler = membershipHandler;
    if (handler != null) return handler(role);
    return RepositoryFailureResult(
      NotFoundError(entityType: 'membership', entityId: role.name),
    );
  }

  @override
  Future<RepositoryResult<AccountRoleProfile>> fetchRoleProfile({
    required HocalistRole role,
  }) async {
    final handler = profileHandler;
    if (handler != null) return handler(role);
    return RepositoryFailureResult(
      NotFoundError(entityType: 'role_profile', entityId: role.name),
    );
  }

  @override
  Future<RepositoryResult<PrivateContactRecord>> fetchPrivateContact() async {
    final handler = contactHandler;
    if (handler != null) return handler();
    return const RepositoryFailureResult(
      NotFoundError(entityType: 'private_contact', entityId: 'contact'),
    );
  }

  @override
  Future<RepositoryResult<OnboardResult>> onboard(
    OnboardCommand command,
  ) async {
    onboardCommands.add(command);
    final future = onboardFuture;
    if (future != null) return future;
    final handler = onboardHandler;
    if (handler != null) return handler(command);
    return RepositorySuccess(
      OnboardResult(
        membershipId: 'membership-${command.role.name}',
        role: command.role,
        revision: 1,
      ),
    );
  }

  @override
  Future<RepositoryResult<RoleProfileUpdateResult>> updateRoleProfile(
    UpdateRoleProfileCommand command,
  ) async {
    profileUpdateCommands.add(command);
    final handler = profileUpdateHandler;
    if (handler != null) return handler(command);
    return RepositorySuccess(
      RoleProfileUpdateResult(
        profileId: command.profileId,
        revision: command.expectedRevision + 1,
      ),
    );
  }

  @override
  Future<RepositoryResult<ContactUpdateResult>> updateContact(
    UpdateContactCommand command,
  ) async {
    contactUpdateCommands.add(command);
    final handler = contactUpdateHandler;
    if (handler != null) return handler(command);
    return RepositorySuccess(
      ContactUpdateResult(revision: command.expectedRevision + 1),
    );
  }
}
