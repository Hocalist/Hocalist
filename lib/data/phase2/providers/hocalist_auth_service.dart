import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

import 'provider_runtime.dart';

/// Authentication only. A valid Auth session is not membership or plan access.
/// The account adapter must authorize the chosen role before entering its UI.
class HocalistAuthService {
  HocalistAuthService(this.client, {this.publishableKey});

  final SupabaseClient client;

  /// Public client key used to build the throwaway reauthentication client.
  /// When absent, password confirmation stays unavailable instead of risking
  /// the signed-in session.
  final String? publishableKey;

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ProviderOperationException {
      rethrow;
    } on AuthException catch (error) {
      throw ProviderOperationException(_safeAuthCode(error));
    } catch (_) {
      throw const ProviderOperationException('authentication_failed');
    }
  }

  /// Maps provider errors to short safe codes. Raw provider messages, status
  /// text and payloads are never propagated to the UI layer.
  static String _safeAuthCode(AuthException error) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'invalid_credentials';
      case 'email_not_confirmed':
        return 'email_not_confirmed';
      case 'user_already_exists':
      case 'email_exists':
        return 'email_already_registered';
      case 'weak_password':
        return 'weak_password';
      case 'otp_expired':
        return 'code_expired';
      case 'same_password':
        return 'password_unchanged';
      case 'reauthentication_needed':
      case 'reauth_nonce_missing':
        return 'reauthentication_required';
      case 'invalid_otp':
      case 'invalid_token':
        return 'invalid_code';
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
      case 'too_many_requests':
        return 'rate_limited';
      case 'phone_exists':
        return 'phone_already_registered';
      case 'signup_disabled':
        return 'signup_disabled';
      case 'validation_failed':
        return 'invalid_input';
    }
    if (error.statusCode == '429') return 'rate_limited';
    return 'authentication_failed';
  }

  Future<void> google() => _run(() async {
    if (hocalistLocalWebTest && !supportsHocalistOAuthReturn(Uri.base)) {
      final destination = hocalistSecurePreviewHandoff(Uri.base);
      if (destination != null) {
        final opened = await launchUrl(destination, webOnlyWindowName: '_self');
        if (opened) return;
      }
      throw const ProviderOperationException('https_preview_required');
    }
    final opened = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: hocalistAuthRedirect,
      authScreenLaunchMode: hocalistLocalWebTest
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!opened) throw const ProviderOperationException('browser_not_opened');
    // Wait for onAuthStateChange in the composition; opening Google is not login.
  });

  Future<AuthResponse> emailLogin(String email, String password) =>
      _run(() async {
        final response = await client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        if (response.user != null && response.user!.emailConfirmedAt == null) {
          await client.auth.signOut(scope: SignOutScope.local);
          throw const ProviderOperationException('email_not_confirmed');
        }
        return response;
      });

  Future<AuthResponse> emailSignup({
    required String email,
    required String password,
    required String name,
  }) => _run(
    () => client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: hocalistAuthRedirect,
      data: {'full_name': name.trim()},
    ),
  );

  Future<void> requestEmailLink({
    required String email,
    required String name,
  }) => _run(
    () => client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: hocalistAuthRedirect,
      shouldCreateUser: true,
      data: {'full_name': name.trim()},
    ),
  );

  /// Sends the provider recovery email. Sending is not a reset; the user still
  /// has to open the link and set a new password.
  Future<void> requestPasswordReset(String email) => _run(
    () => client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: hocalistAuthRedirect,
    ),
  );

  /// Sets a new password for the current session. The session is unchanged;
  /// the controller decides whether it is a recovery session or an
  /// authenticated password change.
  Future<void> updatePassword(String password) =>
      _run(() => client.auth.updateUser(UserAttributes(password: password)));

  /// Starts the provider's email change. The provider keeps it pending until
  /// the new address is confirmed; the active email is unchanged until then.
  Future<void> requestEmailChange(String newEmail) => _run(
    () => client.auth.updateUser(UserAttributes(email: newEmail.trim())),
  );

  /// Verifies the signed-in account's password without touching the signed-in
  /// session. Verification runs on a throwaway client built from the public
  /// key, so an identity replacement can never be clobbered or resurrected by
  /// this call. Without a public key the action is honestly unavailable.
  Future<void> confirmPassword(String password) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const ProviderOperationException('authentication_required');
    }
    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw const ProviderOperationException('reauthentication_unavailable');
    }
    final key = publishableKey;
    if (key == null || key.trim().isEmpty) {
      throw const ProviderOperationException('reauthentication_unavailable');
    }
    final verifier = _buildVerificationClient(key);
    try {
      final response = await verifier.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user?.id != user.id) {
        throw const ProviderOperationException('reauthentication_failed');
      }
    } on AuthException catch (error) {
      throw ProviderOperationException(_safeAuthCode(error));
    } finally {
      // Only the throwaway client's session exists here; drop it.
      try {
        await verifier.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // The verification outcome is unchanged if discard cleanup fails.
      }
    }
  }

  SupabaseClient _buildVerificationClient(String key) {
    final restUrl = client.rest.url;
    const suffix = '/rest/v1';
    final baseUrl = restUrl.endsWith(suffix)
        ? restUrl.substring(0, restUrl.length - suffix.length)
        : restUrl;
    return SupabaseClient(
      baseUrl,
      key,
      httpClient: client.rest.httpClient,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  void _phone(String phone) {
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
      throw const ProviderOperationException('international_phone_required');
    }
  }

  /// Explicit signup/login choice prevents login from silently creating users.
  Future<void> requestPhoneCode(String phone, {required bool signup}) {
    _phone(phone);
    return _run(
      () => client.auth.signInWithOtp(phone: phone, shouldCreateUser: signup),
    );
  }

  Future<AuthResponse> confirmPhoneCode(String phone, String code) {
    _phone(phone);
    if (!RegExp(r'^[0-9]{4,10}$').hasMatch(code)) {
      throw const ProviderOperationException('invalid_verification_code');
    }
    return _run(
      () => client.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms),
    );
  }

  Future<void> logout({required Future<void> Function() disablePush}) async {
    final identity = client.auth.currentUser?.id;
    try {
      await disablePush();
    } finally {
      if (client.auth.currentUser?.id == identity) {
        await client.auth.signOut(scope: SignOutScope.local);
      }
    }
  }
}
