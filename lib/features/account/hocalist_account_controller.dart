/// Real account state wiring for the Hocalist mobile app.
///
/// Owns the gate between a verified Supabase Auth session and the selected
/// buyer/seller membership:
///
/// - Restores sessions from the provider identity, never from the prototype
///   authenticated flag.
/// - Fetches the explicitly selected role through the account adapter; never
///   picks the first membership.
/// - Onboards a missing membership with a stable retry key.
/// - Keeps pending, restricted and disabled memberships out of the app.
/// - Discards stale async results after logout or identity replacement.
///
/// This controller never manufactures privileges and never falls back to
/// simulated authentication.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/phase2/account_contacts.dart';
import '../../domain/phase2/accounts.dart';
import '../../domain/phase2/failures.dart';
import '../../domain/phase2/patch.dart';
import '../../domain/phase2/profiles.dart';
import 'account_auth_gateway.dart';

/// Where the account gate currently is.
enum AccountAccessPhase {
  booting,
  signedOut,
  emailConfirmationPending,
  onboarding,
  membershipPending,
  membershipRestricted,
  active,
  failed,

  /// The session came from a password-recovery link and must set a new
  /// password before any marketplace content loads.
  passwordRecovery,

  /// A recovery email was requested and the provider is sending it.
  recoveryEmailSent,

  /// A recovery link was rejected (expired, used or malformed).
  recoveryLinkExpired,
}

/// Safe, actionable failure raised by controller actions.
class AccountActionException implements Exception {
  const AccountActionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AccountActionException($code)';
}

/// User-facing copy for safe account codes. Unknown codes never leak provider
/// text; they fall back to a generic retry message.
String accountActionMessage(String code) {
  return switch (code) {
    'invalid_credentials' => 'Email or password is not correct.',
    'email_not_confirmed' => 'Confirm your email address before signing in.',
    'email_already_registered' =>
      'An account already uses this email. Log in instead.',
    'weak_password' => 'Choose a stronger password (at least 6 characters).',
    'rate_limited' => 'Too many attempts. Wait a moment and try again.',
    'code_expired' => 'That code expired. Request a new one.',
    'invalid_code' => 'That code is not valid. Check it and try again.',
    'phone_already_registered' =>
      'That phone number is already registered. Log in instead.',
    'international_phone_required' =>
      'Enter the phone number with a country code, for example +14155550123.',
    'invalid_verification_code' =>
      'Enter the verification code from the SMS message.',
    'signup_disabled' => 'New signups are not available right now.',
    'invalid_input' => 'Check the form values and try again.',
    'password_unchanged' => 'Choose a password you have not used before.',
    'email_unchanged' => 'That address is already on the account.',
    'reauthentication_failed' =>
      'That password is not correct for the signed-in account.',
    'reauthentication_unavailable' =>
      'Password confirmation is not available for this account.',
    'recovery_link_expired' =>
      'That reset link is no longer valid. Request a new one.',
    'recovery_link_invalid' =>
      'That reset link did not work. Request a new one.',
    'password_reset_unavailable' =>
      'The reset email could not be sent. Check the address and try again.',
    'email_change_unavailable' =>
      'The email change could not be started. Try again.',
    'network' => 'The connection failed. Check your internet and try again.',
    'authenticate' =>
      'Your sign-in could not be renewed. Try again, or sign out and log in again.',
    'session_changed' =>
      'The signed-in account changed. Sign in again to continue.',
    'duplicate_submit' => 'Please wait for the current request to finish.',
    'logout_failed' => 'Could not sign out. Try again.',
    'onboarding_seed_required' =>
      'This account has no Hocalist profile yet. Contact support.',
    'account_restricted' =>
      'This account is restricted and cannot access the app.',
    'profile_access_denied' => 'This role is not active yet.',
    'contact_access_denied' =>
      'Contacts are available only while a role is active.',
    'membership_exists' => 'A membership for this role already exists.',
    'revision_conflict' =>
      'The profile changed on another device. Refresh and try again.',
    'idempotency_conflict' =>
      'A different change already used this request. Try again.',
    'profile_unavailable' => 'The role profile is not loaded yet. Try again.',
    'contact_unavailable' => 'Contact details are not loaded yet. Try again.',
    'validation' => 'Some values were not accepted. Review them and try again.',
    'malformed_response' =>
      'Something went wrong while loading your account. Try again later.',
    'server' => 'Something went wrong. Try again.',
    'https_preview_required' =>
      'Open the HTTPS test link before continuing with Google. Google cannot return to the Wi-Fi IP address.',
    'authentication_failed' => 'Sign-in failed. Try again.',
    'not_found' => 'The requested account record was not found.',
    'unexpected' => 'Something went wrong. Try again.',
    _ => 'Something went wrong. Try again.',
  };
}

class HocalistAccountController extends ChangeNotifier {
  bool returnToLogin = false;
  factory HocalistAccountController({
    required AccountAuthGateway auth,
    required AccountRepository accounts,
    Future<void> Function()? disablePush,
    String Function()? newIdempotencyKey,
    HocalistRole initialRole = HocalistRole.buyer,
  }) {
    final controller = HocalistAccountController._(
      auth,
      accounts,
      disablePush,
      newIdempotencyKey ?? _randomKey,
    );
    controller._selectedRole = initialRole;
    return controller;
  }

  HocalistAccountController._(
    this._auth,
    this._accounts,
    this._disablePush,
    this._newIdempotencyKey,
  );

  final AccountAuthGateway _auth;
  final AccountRepository _accounts;
  final Future<void> Function()? _disablePush;
  final String Function() _newIdempotencyKey;

  AccountAccessPhase _phase = AccountAccessPhase.booting;
  HocalistRole _selectedRole = HocalistRole.buyer;
  MembershipRecord? _membership;
  AccountRoleProfile? _profile;
  PrivateContactRecord? _contact;
  String? _email;
  String? _suggestedDisplayName;
  bool _busy = false;
  bool _formBusy = false;
  bool _awaitingProvider = false;
  bool _contactUnavailable = false;
  String? _errorCode;
  String? _recoveryEmail;
  AccountRecoverySignal? _recoverySignal;
  String? _passwordChangeMessage;

  StreamSubscription<AuthIdentitySnapshot>? _identitySubscription;
  StreamSubscription<AccountRecoverySignal>? _recoverySubscription;
  AuthIdentitySnapshot _identity = const AuthIdentitySnapshot.signedOut();
  int _generation = 0;
  int _loadToken = 0;
  String? _onboardKey;
  String? _onboardPayload;
  String? _profileKey;
  String? _profilePayload;
  String? _contactKey;
  String? _contactPayload;
  bool _started = false;

  AccountAccessPhase get phase => _phase;
  HocalistRole get selectedRole => _selectedRole;
  MembershipRecord? get membership => _membership;
  AccountRoleProfile? get profile => _profile;
  PrivateContactRecord? get contact => _contact;
  bool get contactUnavailable => _contactUnavailable;
  String? get email => _email ?? _identity.email;

  /// Current provider identity id, or null when signed out.
  String? get userId => _identity.userId;

  /// True while the current session came from a recovery link and has not set
  /// a new password yet.
  bool get recoveryActive => _identity.recovery;

  /// Provider-reported email change awaiting confirmation.
  String? get pendingEmailChange => _identity.pendingEmailChange;

  /// The recovery email address most recently requested.
  String? get recoveryEmail => _recoveryEmail;

  /// Why a recovery link was rejected, when one was.
  AccountRecoverySignal? get recoveryLinkFailure => _recoverySignal;

  /// Result message for the authenticated password/email change forms.
  String? get passwordChangeMessage => _passwordChangeMessage;

  String get suggestedDisplayName =>
      _suggestedDisplayName ?? _identity.displayName ?? '';
  bool get busy => _busy;
  bool get formBusy => _formBusy;
  bool get awaitingProvider => _awaitingProvider;
  String? get errorCode => _errorCode;
  bool get isSignedIn => _identity.isSignedIn;

  /// Safe user-facing copy for the current gate error, if any.
  String? get errorMessage {
    final code = _errorCode;
    return code == null ? null : accountActionMessage(code);
  }

  /// Restores the provider session once and subscribes to identity changes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _identity = _auth.currentIdentity;
    _identitySubscription = _auth.identityChanges.listen(
      _onIdentityChanged,
      onError: (_) {},
    );
    _recoverySubscription = _auth.recoverySignals.listen(
      _onRecoverySignal,
      onError: (_) {},
    );
    await _restore();
  }

  Future<void> _restore() async {
    if (!_identity.isSignedIn) {
      _phase = AccountAccessPhase.signedOut;
      _notify();
      return;
    }
    if (_identity.recovery) {
      _phase = AccountAccessPhase.passwordRecovery;
      _notify();
      return;
    }
    await _loadSelectedRole();
  }

  void _onRecoverySignal(AccountRecoverySignal signal) {
    if (_identity.isSignedIn) {
      // A recovery failure while already signed in does not replace the app;
      // the security screen surfaces the code from its own action.
      return;
    }
    _recoverySignal = signal;
    _clearMembershipState();
    _busy = false;
    _formBusy = false;
    _phase = AccountAccessPhase.recoveryLinkExpired;
    _notify();
  }

  void _onIdentityChanged(AuthIdentitySnapshot next) {
    final identityChanged = next.userId != _identity.userId;
    if (!identityChanged && _identity.recovery && !next.recovery) {
      // A recovery session only completes through the explicit password-update
      // action below. An ordinary same-user refresh or user-update event must
      // not clear the gate, so the latch is preserved here even if a provider
      // snapshot arrives unlatched.
      next = next.copyWith(recovery: true);
    }
    final recoveryChanged = next.recovery != _identity.recovery;
    final pendingEmailChanged =
        next.pendingEmailChange != _identity.pendingEmailChange;
    _identity = next;
    if (!identityChanged && !recoveryChanged) {
      // Same identity, for example a token refresh or an email-change
      // confirmation: keep the current navigation, phase and loaded records.
      if (pendingEmailChanged) _notify();
      return;
    }
    if (!identityChanged && recoveryChanged) {
      // A recovery link was consumed for the current identity. Close the app
      // subtree before any marketplace content is evaluated.
      _generation++;
      _loadToken++;
      _clearPrivateState();
      _awaitingProvider = false;
      _formBusy = false;
      if (!next.isSignedIn) {
        _phase = AccountAccessPhase.signedOut;
        _busy = false;
        _notify();
        return;
      }
      // next.recovery is true here; the false direction is never an event.
      _phase = AccountAccessPhase.passwordRecovery;
      _busy = true;
      _notify();
      return;
    }
    // Identity replacement: invalidate outstanding work and close the gate
    // immediately, before the new identity's membership is fetched. The
    // previous identity's app content must not stay mounted while loading.
    _generation++;
    _loadToken++;
    _clearPrivateState();
    _awaitingProvider = false;
    _formBusy = false;
    if (next.isSignedIn) {
      _phase = next.recovery
          ? AccountAccessPhase.passwordRecovery
          : AccountAccessPhase.booting;
      _busy = !next.recovery;
      _notify();
      if (!next.recovery) unawaited(_loadSelectedRole());
    } else {
      _phase = AccountAccessPhase.signedOut;
      _busy = false;
      _notify();
    }
  }

  /// Explicit buyer/seller selection; the gate never guesses the role.
  void selectRole(HocalistRole role) {
    if (role == _selectedRole) return;
    _selectedRole = role;
    _clearMembershipState();
    _errorCode = null;
    if (_identity.isSignedIn) {
      _phase = AccountAccessPhase.booting;
      _notify();
      unawaited(_loadSelectedRole());
    } else {
      _phase = AccountAccessPhase.signedOut;
      _notify();
    }
  }

  /// Fetches the selected membership and profile for the current identity.
  Future<void> refresh() => _loadSelectedRole();

  Future<void> _loadSelectedRole() async {
    final token = ++_loadToken;
    final generation = _generation;
    final userId = _identity.userId;
    if (userId == null) {
      _phase = AccountAccessPhase.signedOut;
      _notify();
      return;
    }
    if (_identity.recovery) {
      // A recovery session must set a new password before any membership or
      // marketplace data loads.
      _busy = false;
      _phase = AccountAccessPhase.passwordRecovery;
      _notify();
      return;
    }
    _busy = true;
    _errorCode = null;
    _notify();

    final membershipResult = await _accounts.fetchMembership(
      role: _selectedRole,
    );
    if (!_isCurrent(token, generation, userId)) return;
    if (membershipResult.isFailure) {
      final error = membershipResult.errorOrNull!;
      if (error is NotFoundError) {
        _membership = null;
        _profile = null;
        _contact = null;
        _phase = AccountAccessPhase.onboarding;
        _finishLoad();
        return;
      }
      _fail(error);
      return;
    }

    final membership = membershipResult.valueOrNull!;
    _membership = membership;
    if (membership.status == MembershipStatus.pending) {
      _profile = null;
      _contact = null;
      _phase = AccountAccessPhase.membershipPending;
      _finishLoad();
      return;
    }
    if (membership.status != MembershipStatus.active) {
      _profile = null;
      _contact = null;
      _phase = AccountAccessPhase.membershipRestricted;
      _finishLoad();
      return;
    }

    final profileResult = await _accounts.fetchRoleProfile(role: _selectedRole);
    if (!_isCurrent(token, generation, userId)) return;
    if (profileResult.isFailure) {
      _fail(profileResult.errorOrNull!);
      return;
    }
    _profile = profileResult.valueOrNull;

    // Contacts are optional private data and never gate access. A missing row
    // (or hidden contact) leaves the record empty; a transport failure is
    // reported as unavailable instead of pretending it was empty.
    final contactResult = await _accounts.fetchPrivateContact();
    if (!_isCurrent(token, generation, userId)) return;
    if (contactResult.isSuccess) {
      _contact = contactResult.valueOrNull;
      _contactUnavailable = false;
    } else {
      _contact = null;
      _contactUnavailable = contactResult.errorOrNull is! NotFoundError;
    }

    _phase = AccountAccessPhase.active;
    _finishLoad();
  }

  bool _isCurrent(int token, int generation, String userId) =>
      token == _loadToken &&
      generation == _generation &&
      userId == _identity.userId;

  /// True while the captured identity is still the signed-in identity and no
  /// replacement/logout happened since it was captured.
  bool _isIdentityCurrent(int generation, String? userId) =>
      generation == _generation && userId != null && userId == _identity.userId;

  /// Fences every step of a sensitive multi-step action: a mutation must not
  /// run for an identity that was replaced while reauthentication was pending.
  void _requireIdentityCurrent(int generation, String? userId) {
    if (!_isIdentityCurrent(generation, userId)) {
      throw const AccountActionException(
        'session_changed',
        'The signed-in account changed. Sign in again to continue.',
      );
    }
  }

  void _finishLoad() {
    _busy = false;
    _notify();
  }

  void _fail(RepositoryError error) {
    final code = _safeCodeFor(error);
    _errorCode = code;
    _phase = AccountAccessPhase.failed;
    _busy = false;
    _notify();
  }

  String _safeCodeFor(RepositoryError error) {
    return switch (error) {
      NetworkError() => 'network',
      PermissionDeniedError(:final action) => action,
      ConflictError(:final conflictCode) => conflictCode,
      NotFoundError() => 'not_found',
      ValidationError() => 'validation',
      MalformedResponseError() => 'malformed_response',
      ServerError() => 'server',
      LimitExceededError() => 'limit_exceeded',
    };
  }

  /// Clears a gate-level error without changing the phase.
  void clearError() {
    if (_errorCode == null) return;
    _errorCode = null;
    _notify();
  }

  /// Returns to the signed-out form after a pending email confirmation.
  void leaveConfirmationPending() {
    returnToLogin = true;
    _phase = AccountAccessPhase.signedOut;
    _clearMembershipState();
    _notify();
  }

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) {
    return _runForm(() async {
      final outcome = await _auth.signUpWithEmail(
        email: email,
        password: password,
        name: name,
      );
      _email = email.trim();
      _suggestedDisplayName = name.trim();
      if (outcome.confirmationRequired) {
        _clearMembershipState();
        _phase = AccountAccessPhase.emailConfirmationPending;
        _notify();
        return;
      }
      _adoptCurrentIdentity();
      if (!_identity.isSignedIn) {
        throw const AccountAuthException('authentication_failed');
      }
      await _loadSelectedRole();
    });
  }

  Future<void> logInWithEmail({
    required String email,
    required String password,
  }) {
    return _runForm(() async {
      await _auth.logInWithEmail(email: email, password: password);
      _email = email.trim();
      _adoptCurrentIdentity();
      if (!_identity.isSignedIn) {
        throw const AccountAuthException('authentication_failed');
      }
      await _loadSelectedRole();
    });
  }

  Future<void> signInWithGoogle() {
    return _runForm(() async {
      await _auth.signInWithGoogle();
      // The browser opened; completion arrives through identityChanges.
      _awaitingProvider = true;
      _notify();
    });
  }

  Future<void> requestEmailLink({required String email, required String name}) {
    return _runForm(() async {
      await _auth.requestEmailLink(email: email, name: name);
      _email = email.trim();
      _suggestedDisplayName = name.trim();
      _awaitingProvider = true;
      _notify();
    });
  }

  Future<void> requestPhoneCode({
    required String phone,
    required bool signup,
    String? name,
  }) {
    if (signup && name != null && name.trim().isNotEmpty) {
      _suggestedDisplayName = name.trim();
    }
    return _runForm(() => _auth.requestPhoneCode(phone: phone, signup: signup));
  }

  Future<void> confirmPhoneCode({
    required String phone,
    required String code,
    String? name,
  }) {
    return _runForm(() async {
      await _auth.confirmPhoneCode(phone: phone, code: code);
      _adoptCurrentIdentity();
      if (name != null && name.trim().isNotEmpty) {
        _suggestedDisplayName = name.trim();
      }
      if (!_identity.isSignedIn) {
        throw const AccountAuthException('authentication_failed');
      }
      await _loadSelectedRole();
    });
  }

  /// Sends the provider recovery email. A sent email is not a reset: the
  /// recovery session only starts when the user opens the link.
  Future<void> requestPasswordReset({required String email}) {
    return _runForm(() async {
      await _auth.requestPasswordReset(email: email);
      _recoveryEmail = email.trim();
      _recoverySignal = null;
      _phase = AccountAccessPhase.recoveryEmailSent;
      _notify();
    });
  }

  /// Returns from the "check your email" state to the signed-out form.
  void leaveRecoveryEmailSent() {
    returnToLogin = true;
    _recoveryEmail = null;
    _phase = AccountAccessPhase.signedOut;
    _notify();
  }

  /// Returns from the expired-link state to the signed-out form.
  void leaveRecoveryLinkExpired() {
    returnToLogin = true;
    _recoverySignal = null;
    _phase = AccountAccessPhase.signedOut;
    _notify();
  }

  /// Sets the new password for the active recovery session, then continues to
  /// the account gate. The recovery session never renders app content first.
  Future<void> updateRecoveredPassword({required String password}) {
    return _runForm(() async {
      if (!_identity.recovery || !_identity.isSignedIn) {
        throw const AccountActionException(
          'recovery_link_invalid',
          'That reset link did not work. Request a new one.',
        );
      }
      final generation = _generation;
      final userId = _identity.userId;
      await _auth.updatePassword(password: password);
      _requireIdentityCurrent(generation, userId);
      _recoveryEmail = null;
      _recoverySignal = null;
      _identity = _identity.copyWith(recovery: false);
      _phase = AccountAccessPhase.booting;
      _busy = true;
      _notify();
      await _loadSelectedRole();
    });
  }

  /// Confirms the account password for a sensitive action without changing
  /// the session. Throws a safe [AccountActionException] when it does not
  /// match or when the identity changed while confirming.
  Future<void> reauthenticate(String password) {
    return _runForm(() async {
      if (!_identity.isSignedIn) {
        throw const AccountActionException(
          'session_changed',
          'Sign in again to continue.',
        );
      }
      final generation = _generation;
      final userId = _identity.userId;
      await _auth.confirmPassword(password: password);
      _requireIdentityCurrent(generation, userId);
    });
  }

  /// Authenticated password change. Reauthenticates with the current password,
  /// then sets the new one. The session and gate stay where they were, and a
  /// replacement during reauthentication cancels the mutation.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _runForm(() async {
      if (!_identity.isSignedIn) {
        throw const AccountActionException(
          'session_changed',
          'Sign in again to change your password.',
        );
      }
      final generation = _generation;
      final userId = _identity.userId;
      await _auth.confirmPassword(password: currentPassword);
      _requireIdentityCurrent(generation, userId);
      await _auth.updatePassword(password: newPassword);
      _requireIdentityCurrent(generation, userId);
      _passwordChangeMessage = 'Password updated.';
      _notify();
    });
  }

  /// Starts an email change after reauthentication. The provider keeps the new
  /// address pending until it is confirmed, and a replacement during
  /// reauthentication cancels the change.
  Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) {
    return _runForm(() async {
      if (!_identity.isSignedIn) {
        throw const AccountActionException(
          'session_changed',
          'Sign in again to change your email.',
        );
      }
      final current = _identity.email?.trim().toLowerCase();
      if (current != null &&
          current.isNotEmpty &&
          current == newEmail.trim().toLowerCase()) {
        throw const AccountActionException(
          'email_unchanged',
          'That address is already on the account.',
        );
      }
      final generation = _generation;
      final userId = _identity.userId;
      await _auth.confirmPassword(password: currentPassword);
      _requireIdentityCurrent(generation, userId);
      await _auth.requestEmailChange(newEmail: newEmail);
      _requireIdentityCurrent(generation, userId);
      _adoptCurrentIdentity();
      _passwordChangeMessage =
          'Confirmation sent. The new address becomes active after it is '
          'confirmed.';
      _notify();
    });
  }

  void clearPasswordChangeMessage() {
    if (_passwordChangeMessage == null) return;
    _passwordChangeMessage = null;
    _notify();
  }

  /// Creates the missing membership for the selected role.
  ///
  /// The idempotency key is stable across retries of the same payload so a
  /// lost response can be retried safely.
  Future<void> onboardSelectedRole({required String displayName}) {
    return _runForm(() async {
      final trimmed = displayName.trim();
      final payload = '${_selectedRole.name}\u0000$trimmed';
      if (_onboardKey == null || _onboardPayload != payload) {
        _onboardKey = _newIdempotencyKey();
        _onboardPayload = payload;
      }
      final result = await _accounts.onboard(
        OnboardCommand(
          role: _selectedRole,
          displayName: trimmed,
          idempotencyKey: _onboardKey!,
        ),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        if (error is ConflictError &&
            error.conflictCode == 'membership_exists') {
          _onboardKey = null;
          _onboardPayload = null;
          await _loadSelectedRole();
          return;
        }
        throw _toActionException(error);
      }
      _onboardKey = null;
      _onboardPayload = null;
      _suggestedDisplayName = trimmed;
      await _loadSelectedRole();
    });
  }

  /// Saves the selected role's display name at its expected revision.
  Future<void> updateDisplayName(String displayName) {
    return _runForm(() async {
      final current = _profile;
      if (current == null) {
        throw const AccountActionException(
          'profile_unavailable',
          'The role profile is not loaded yet. Try again.',
        );
      }
      final trimmed = displayName.trim();
      if (trimmed == current.displayName) return;
      final payload =
          '${current.membershipId}\u0000${current.stamp.revision}\u0000$trimmed';
      if (_profileKey == null || _profilePayload != payload) {
        _profileKey = _newIdempotencyKey();
        _profilePayload = payload;
      }
      final result = await _accounts.updateRoleProfile(
        UpdateRoleProfileCommand(
          profileId: current.membershipId,
          expectedRevision: current.stamp.revision,
          displayName: trimmed,
          idempotencyKey: _profileKey!,
        ),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        if (error is ConflictError &&
            error.conflictCode == 'revision_conflict') {
          _profileKey = null;
          _profilePayload = null;
          await _loadSelectedRole();
        }
        throw _toActionException(error);
      }
      _profileKey = null;
      _profilePayload = null;
      await _loadSelectedRole();
    });
  }

  /// Saves profile patches at the revision captured when editing began.
  Future<void> updateProfileDetails(UpdateRoleProfileCommand command) {
    return _runForm(() async {
      final current = _profile;
      if (current == null || current.membershipId != command.profileId) {
        throw const AccountActionException(
          'profile_unavailable',
          'Your profile changed. Reopen the editor.',
        );
      }
      final result = await _accounts.updateRoleProfile(command);
      if (result.isFailure) {
        final error = result.errorOrNull!;
        if (error is ConflictError &&
            error.conflictCode == 'revision_conflict') {
          await _loadSelectedRole();
        }
        throw _toActionException(error);
      }
      await _loadSelectedRole();
    });
  }

  /// Saves the shared private contact row at its own expected revision.
  ///
  /// Keep/set/clear semantics come from the caller's [build] function; the
  /// adapter owns encoding. No contact value is ever logged here.
  Future<void> updateContact(
    UpdateContactCommand Function(PrivateContactRecord current) build,
  ) {
    return _runForm(() async {
      final current = _contact;
      if (current == null) {
        throw const AccountActionException(
          'contact_unavailable',
          'Contact details are not loaded yet. Try again.',
        );
      }
      final command = build(current);
      final payload =
          '${current.stamp.revision}\u0000'
          '${_patchSignature(command.phone)}|${_patchSignature(command.addressLine1)}|'
          '${_patchSignature(command.addressLine2)}|${_patchSignature(command.city)}|'
          '${_patchSignature(command.region)}|${_patchSignature(command.postalCode)}|'
          '${_patchSignature(command.countryCode)}';
      if (_contactKey == null || _contactPayload != payload) {
        _contactKey = _newIdempotencyKey();
        _contactPayload = payload;
      }
      final result = await _accounts.updateContact(
        UpdateContactCommand(
          expectedRevision: command.expectedRevision,
          phone: command.phone,
          addressLine1: command.addressLine1,
          addressLine2: command.addressLine2,
          city: command.city,
          region: command.region,
          postalCode: command.postalCode,
          countryCode: command.countryCode,
          idempotencyKey: _contactKey!,
        ),
      );
      if (result.isFailure) {
        final error = result.errorOrNull!;
        if (error is ConflictError &&
            error.conflictCode == 'revision_conflict') {
          _contactKey = null;
          _contactPayload = null;
          await _loadSelectedRole();
        }
        throw _toActionException(error);
      }
      _contactKey = null;
      _contactPayload = null;
      await _loadSelectedRole();
    });
  }

  String _patchSignature(Patch<Object?> patch) => switch (patch) {
    PatchKeep<Object?>() => 'k',
    PatchClear<Object?>() => 'c',
    PatchSet<Object?>(:final value) => 's:$value',
  };

  /// Push cleanup happens before local sign-out; a cleanup failure never
  /// leaves the user signed in and never signs out a replacement identity.
  Future<void> logout() async {
    final generation = _generation;
    _busy = true;
    _errorCode = null;
    _notify();
    try {
      await _auth.logout(disablePush: _disablePush ?? () async {});
    } catch (_) {
      // The gateway signs out locally even when cleanup fails; state below is
      // verified from the provider instead of assumed.
    }
    if (generation != _generation) {
      _busy = false;
      _notify();
      return;
    }
    _adoptCurrentIdentity();
    if (_identity.isSignedIn) {
      // The caller receives the safe failure and renders it inline; the gate
      // body keeps its own state instead of being overwritten by logout.
      _busy = false;
      _notify();
      throw const AccountActionException(
        'logout_failed',
        'Could not sign out. Try again.',
      );
    }
    _clearPrivateState();
    _phase = AccountAccessPhase.signedOut;
    _busy = false;
    _notify();
  }

  Future<void> _runForm(Future<void> Function() action) async {
    if (_formBusy) {
      throw const AccountActionException(
        'duplicate_submit',
        'Please wait for the current request to finish.',
      );
    }
    _formBusy = true;
    _errorCode = null;
    _notify();
    try {
      await action();
    } catch (error) {
      throw _toActionException(error);
    } finally {
      _formBusy = false;
      _notify();
    }
  }

  AccountActionException _toActionException(Object error) {
    if (error is AccountActionException) return error;
    if (error is AccountAuthException) {
      return AccountActionException(
        error.code,
        accountActionMessage(error.code),
      );
    }
    if (error is RepositoryError) {
      final code = _safeCodeFor(error);
      return AccountActionException(code, accountActionMessage(code));
    }
    return const AccountActionException(
      'unexpected',
      'Something went wrong. Try again.',
    );
  }

  /// Re-reads the provider identity after an auth action so the gate never
  /// relies on a stale snapshot.
  void _adoptCurrentIdentity() {
    final next = _auth.currentIdentity;
    if (next.userId != _identity.userId) {
      _identity = next;
      _generation++;
      _clearPrivateState();
      return;
    }
    _identity = AuthIdentitySnapshot(
      userId: next.userId,
      email: next.email,
      displayName: next.displayName,
      recovery: _identity.recovery,
      pendingEmailChange: next.pendingEmailChange,
    );
  }

  void _clearMembershipState() {
    _membership = null;
    _profile = null;
    _contact = null;
    _contactUnavailable = false;
    _onboardKey = null;
    _onboardPayload = null;
    _profileKey = null;
    _profilePayload = null;
    _contactKey = null;
    _contactPayload = null;
  }

  void _clearPrivateState() {
    _clearMembershipState();
    _email = null;
    _suggestedDisplayName = null;
    _recoveryEmail = null;
    _recoverySignal = null;
    _passwordChangeMessage = null;
  }

  void _notify() {
    if (!hasListeners) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _identitySubscription?.cancel();
    _identitySubscription = null;
    _recoverySubscription?.cancel();
    _recoverySubscription = null;
    super.dispose();
  }

  static String _randomKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
