/// Supabase implementation of the account auth gateway.
///
/// Wraps the existing [HocalistAuthService] and exposes auth-state identity
/// changes. No credential or raw provider payload is read or logged.
///
/// Recovery sessions are latched: once a `passwordRecovery` event is observed
/// for a user, that user's snapshots keep `recovery: true` across ordinary
/// token refreshes, initial sessions and user-update events until either the
/// password is explicitly updated through this gateway or the identity changes
/// or signs out. A refresh event can never complete a recovery session.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/account/account_auth_gateway.dart';
import 'hocalist_auth_service.dart';
import 'provider_runtime.dart';

class SupabaseAccountAuthGateway implements AccountAuthGateway {
  SupabaseAccountAuthGateway(this.client, {String? publishableKey})
    : _auth = HocalistAuthService(client, publishableKey: publishableKey) {
    _authSubscription = client.auth.onAuthStateChange.listen(
      _onAuthStateChanged,
      onError: (_) {},
    );
  }

  final SupabaseClient client;
  final HocalistAuthService _auth;
  late final StreamSubscription<AuthState> _authSubscription;
  final StreamController<AuthIdentitySnapshot> _identityController =
      StreamController<AuthIdentitySnapshot>.broadcast();

  /// User id whose recovery session is latched until an explicit completion,
  /// sign-out or identity replacement.
  String? _recoveryUserId;

  void _onAuthStateChanged(AuthState state) {
    final user = state.session?.user;
    if (state.event == AuthChangeEvent.passwordRecovery && user != null) {
      _recoveryUserId = user.id;
    } else if (user == null || user.id != _recoveryUserId) {
      // Sign-out or a different identity clears the latch. Same-user refresh,
      // user-updated and initial-session events keep it.
      _recoveryUserId = null;
    }
    if (!_identityController.isClosed) {
      _identityController.add(_snapshot(user, event: state.event));
    }
  }

  /// Converts provider-layer failures into safe gateway codes.
  Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AccountAuthException {
      rethrow;
    } on ProviderOperationException catch (error) {
      throw AccountAuthException(error.code);
    } catch (_) {
      throw const AccountAuthException('authentication_failed');
    }
  }

  AuthIdentitySnapshot _snapshot(User? user, {AuthChangeEvent? event}) {
    if (user == null) return const AuthIdentitySnapshot.signedOut();
    final metadata = user.userMetadata;
    final name = metadata?['full_name'] ?? metadata?['name'];
    return AuthIdentitySnapshot(
      userId: user.id,
      email: user.email,
      displayName: name is String && name.trim().isNotEmpty ? name : null,
      recovery:
          event == AuthChangeEvent.passwordRecovery ||
          user.id == _recoveryUserId,
      pendingEmailChange: user.emailChangeSentAt == null
          ? null
          : (user.newEmail != null && user.newEmail!.trim().isNotEmpty
                ? user.newEmail
                : null),
    );
  }

  static AccountRecoverySignal _recoverySignalFor(Object error) {
    if (error is AuthException && error.code == 'otp_expired') {
      return const AccountRecoverySignal(AccountRecoverySignalKind.expired);
    }
    return const AccountRecoverySignal(AccountRecoverySignalKind.invalid);
  }

  @override
  AuthIdentitySnapshot get currentIdentity =>
      _snapshot(client.auth.currentUser);

  @override
  Stream<AuthIdentitySnapshot> get identityChanges =>
      Stream<AuthIdentitySnapshot>.multi((controller) {
        // Seed the current snapshot so a consumer that subscribes after the
        // recovery event still receives the latched state exactly once.
        controller.add(currentIdentity);
        final subscription = _identityController.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      });

  @override
  Stream<AccountRecoverySignal> get recoverySignals =>
      client.auth.onAuthStateChange.transform(
        StreamTransformer<AuthState, AccountRecoverySignal>.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.add(_recoverySignalFor(error)),
        ),
      );

  @override
  Future<EmailSignupOutcome> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) => _translate(() async {
    final response = await _auth.emailSignup(
      email: email,
      password: password,
      name: name,
    );
    return EmailSignupOutcome(confirmationRequired: response.session == null);
  });

  @override
  Future<void> logInWithEmail({
    required String email,
    required String password,
  }) => _translate(() => _auth.emailLogin(email, password));

  @override
  Future<void> requestEmailLink({
    required String email,
    required String name,
  }) => _translate(() => _auth.requestEmailLink(email: email, name: name));

  @override
  Future<void> signInWithGoogle() => _translate(_auth.google);

  @override
  Future<void> requestPhoneCode({
    required String phone,
    required bool signup,
  }) => _translate(() => _auth.requestPhoneCode(phone, signup: signup));

  @override
  Future<void> confirmPhoneCode({
    required String phone,
    required String code,
  }) => _translate(() => _auth.confirmPhoneCode(phone, code));

  @override
  Future<void> requestPasswordReset({required String email}) =>
      _translate(() => _auth.requestPasswordReset(email));

  @override
  Future<void> updatePassword({required String password}) async {
    await _translate(() => _auth.updatePassword(password));
    // Explicit acknowledgement: the reset succeeded, so the latch is cleared
    // and the completion snapshot is emitted for listeners.
    _recoveryUserId = null;
    if (!_identityController.isClosed) {
      _identityController.add(currentIdentity);
    }
  }

  @override
  Future<void> requestEmailChange({required String newEmail}) =>
      _translate(() => _auth.requestEmailChange(newEmail));

  @override
  Future<void> confirmPassword({required String password}) =>
      _translate(() => _auth.confirmPassword(password));

  @override
  Future<void> logout({required Future<void> Function() disablePush}) async {
    await _translate(() => _auth.logout(disablePush: disablePush));
    _recoveryUserId = null;
  }

  /// Releases the provider subscription and stream. Optional: the gateway is
  /// recreated per session composition.
  Future<void> dispose() async {
    await _authSubscription.cancel();
    await _identityController.close();
  }
}
