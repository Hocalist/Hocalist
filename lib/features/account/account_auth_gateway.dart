/// Authentication boundary for the real account UI.
///
/// Pure Dart on purpose: the account controller and its tests depend on this
/// interface, while the Supabase implementation lives in the provider layer.
/// A valid Auth session is not membership or plan access; the account adapter
/// still authorizes the explicitly selected role.
library;

import '../../domain/phase2/accounts.dart';

/// Minimal safe identity view. Never carries tokens or provider payloads.
class AuthIdentitySnapshot {
  const AuthIdentitySnapshot({
    this.userId,
    this.email,
    this.displayName,
    this.recovery = false,
    this.pendingEmailChange,
  });

  const AuthIdentitySnapshot.signedOut()
    : userId = null,
      email = null,
      displayName = null,
      recovery = false,
      pendingEmailChange = null;

  final String? userId;
  final String? email;

  /// Optional `full_name` metadata, used only to prefill the onboarding form.
  final String? displayName;

  /// True only for the session created by a password-recovery link, before the
  /// user sets a new password. The gate must not load marketplace content while
  /// this is set.
  final bool recovery;

  /// Provider-reported email change awaiting confirmation, when one is
  /// pending. The address is not active until the provider confirms it.
  final String? pendingEmailChange;

  bool get isSignedIn => userId != null;

  AuthIdentitySnapshot copyWith({
    String? userId,
    String? email,
    String? displayName,
    bool? recovery,
    String? pendingEmailChange,
  }) {
    return AuthIdentitySnapshot(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      recovery: recovery ?? this.recovery,
      pendingEmailChange: pendingEmailChange ?? this.pendingEmailChange,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthIdentitySnapshot &&
      other.userId == userId &&
      other.email == email &&
      other.displayName == displayName &&
      other.recovery == recovery &&
      other.pendingEmailChange == pendingEmailChange;

  @override
  int get hashCode =>
      Object.hash(userId, email, displayName, recovery, pendingEmailChange);

  @override
  String toString() =>
      'AuthIdentitySnapshot(signedIn: $isSignedIn, email: [redacted])';
}

/// A recovery-link failure reported by the provider or deep-link handling.
///
/// `expired` is a link past its validity window; `invalid` is a malformed,
/// already-used or unknown link. Both must show a clear retry path instead of
/// a signed-out form that pretends nothing arrived.
enum AccountRecoverySignalKind { expired, invalid }

class AccountRecoverySignal {
  const AccountRecoverySignal(this.kind);

  final AccountRecoverySignalKind kind;

  @override
  bool operator ==(Object other) =>
      other is AccountRecoverySignal && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'AccountRecoverySignal(${kind.name})';
}

/// Result of an email signup attempt.
///
/// When the project requires email confirmation, Supabase returns no session:
/// that is a pending state, never a successful login.
class EmailSignupOutcome {
  const EmailSignupOutcome({required this.confirmationRequired});

  final bool confirmationRequired;

  @override
  String toString() =>
      'EmailSignupOutcome(confirmationRequired: $confirmationRequired)';
}

/// Safe auth failure code raised by gateway implementations.
///
/// The code is a short stable string such as `invalid_credentials`,
/// `rate_limited` or `code_expired`; raw provider text is never included.
class AccountAuthException implements Exception {
  const AccountAuthException(this.code);

  final String code;

  @override
  String toString() => 'AccountAuthException($code)';
}

/// Provider auth operations used by the account controller.
///
/// Implementations must map provider failures to safe short codes (for example
/// `invalid_credentials`, `rate_limited`, `code_expired`) and never surface raw
/// provider messages or payloads.
abstract interface class AccountAuthGateway {
  AuthIdentitySnapshot get currentIdentity;

  /// Emits on sign-in, sign-out and identity replacement. Token refreshes for
  /// the same identity may be emitted; consumers compare [userId].
  Stream<AuthIdentitySnapshot> get identityChanges;

  Future<EmailSignupOutcome> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  });

  Future<void> logInWithEmail({
    required String email,
    required String password,
  });

  /// Sends a passwordless email link for the loopback development preview.
  /// The Auth identity is still delivered through [identityChanges].
  Future<void> requestEmailLink({required String email, required String name});

  /// Opens the external Google browser. Completion arrives through
  /// [identityChanges]; opening a browser is not a login.
  Future<void> signInWithGoogle();

  Future<void> requestPhoneCode({required String phone, required bool signup});

  Future<void> confirmPhoneCode({required String phone, required String code});

  /// Recovery-link failures that are not identity changes. Implementations that
  /// cannot surface them keep the stream empty; the request form stays
  /// reachable from every recovery state.
  Stream<AccountRecoverySignal> get recoverySignals;

  /// Sends the provider's password-recovery email. Sending is not a reset:
  /// the user still has to open the link and set a new password.
  Future<void> requestPasswordReset({required String email});

  /// Sets a new password for the current session. Only valid for a
  /// recovery session or an already-authenticated user.
  Future<void> updatePassword({required String password});

  /// Starts an email change. The provider keeps the change pending until the
  /// user confirms it from the new address.
  Future<void> requestEmailChange({required String newEmail});

  /// Verifies the current account password without replacing the session.
  /// Used to reauthenticate sensitive account actions. Throws
  /// [AccountAuthException] with `invalid_credentials` on a wrong password.
  Future<void> confirmPassword({required String password});

  /// Cleans up push state before local sign-out. Implementations must not sign
  /// out a replacement identity if the session changed during cleanup.
  Future<void> logout({required Future<void> Function() disablePush});
}

/// Service bundle the real account bootstrap needs.
///
/// Implemented by the production provider composition and by tests, so the
/// app entry point can be exercised without a live provider.
abstract interface class HocalistAccountServices {
  AccountAuthGateway get accountAuth;
  AccountRepository get accounts;

  /// Push cleanup that runs before local sign-out.
  Future<void> Function() get disablePush;
}
